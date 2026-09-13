# R/hedging_scanner.R
# Production-grade scanner for detecting submanager conviction hedging

library(dplyr)
library(tidyr)

calculate_hedging <- function(institutional_data, 
                                  min_position_value = 1000000,
                                  min_hedging_threshold = 20) {
  
  cat("================================================================\n")
  cat("SUBMANAGER HEDGING SCANNER\n")
  cat("================================================================\n\n")
  
  cat("Analyzing institutional positions for hedging signals...\n\n")
  
  stock_positions <- institutional_data %>%
    filter(
      putCall == "",
      value >= min_position_value,
      shrsOrPrnAmt > 0,
      QOQSshPrnAmt != 0
    ) %>%
    mutate(
      old_shares = shrsOrPrnAmt - QOQSshPrnAmt,
      pct_change = (QOQSshPrnAmt / old_shares) * 100
    ) %>%
    filter(!is.infinite(pct_change), !is.na(pct_change))
  
  cat("Filtered to", nrow(stock_positions), "significant stock positions\n\n")
  
  hedging_analysis <- stock_positions %>%
    group_by(issuerQkid, issuer, issuerTicker) %>%
    summarise(
      n_submanagers = n(),
      total_value = sum(value),
      total_shares = sum(shrsOrPrnAmt),
      avg_pct_change = mean(pct_change),
      max_pct_change = max(pct_change),
      min_pct_change = min(pct_change),
      sd_pct_change = sd(pct_change),
      range_pct_change = max_pct_change - min_pct_change,
      n_buying = sum(pct_change > 0),
      n_selling = sum(pct_change < 0),
      n_flat = sum(pct_change == 0),
      total_qoq_change = sum(QOQSshPrnAmt),
      .groups = "drop"
    ) %>%
    mutate(
      old_total_shares = total_shares - total_qoq_change,
      agg_pct_change = ifelse(old_total_shares != 0,
                              (total_qoq_change / old_total_shares) * 100,
                              NA),
      has_hedging = (n_buying > 0 & n_selling > 0),
      hedging_magnitude = range_pct_change,
      hedging_score = case_when(
        !has_hedging ~ 0,
        range_pct_change >= 100 ~ 100,
        range_pct_change >= 50 ~ 75,
        range_pct_change >= min_hedging_threshold ~ 50,
        TRUE ~ 25
      )
    ) %>%
    filter(
      n_submanagers >= 2,
      has_hedging,
      hedging_magnitude >= min_hedging_threshold
    ) %>%
    arrange(desc(hedging_score), desc(hedging_magnitude))
  
  cat("Found", nrow(hedging_analysis), "stocks with submanager hedging\n\n")
  
  return(hedging_analysis)
}

get_hedging_detail <- function(institutional_data, ticker_symbol) {
  ticker_upper <- toupper(ticker_symbol)
  
  positions <- institutional_data %>%
    filter(issuerTicker == ticker_upper, putCall == "", shrsOrPrnAmt > 0) %>%
    mutate(
      old_shares = shrsOrPrnAmt - QOQSshPrnAmt,
      pct_change = ifelse(old_shares != 0, (QOQSshPrnAmt / old_shares) * 100, NA),
      direction = case_when(
        pct_change > 15 ~ "STRONG BUY",
        pct_change > 0 ~ "BUY",
        pct_change < -15 ~ "STRONG SELL",
        pct_change < 0 ~ "SELL",
        TRUE ~ "HOLD"
      )
    ) %>%
    select(otherManagerName, shares = shrsOrPrnAmt, value,
           qoq_share_change = QOQSshPrnAmt, qoq_value_change = QOQValue,
           pct_change, direction, quarters_held = QtrsHeld) %>%
    arrange(desc(pct_change))
  
  return(positions)
}

scan_hedging_opportunities <- function(institutional_data, top_n = 20, export_csv = TRUE) {
  cat("\n================================================================\n")
  cat("HEDGING OPPORTUNITY SCANNER\n")
  cat("================================================================\n\n")
  
  hedging_results <- calculate_hedging(institutional_data)
  
  if (nrow(hedging_results) == 0) {
    cat("⚠ No hedging opportunities found\n")
    return(list(summary = NULL, detailed = NULL))
  }
  
  top_opportunities <- head(hedging_results, top_n)
  
  cat("================================================================\n")
  cat("TOP HEDGING OPPORTUNITIES\n")
  cat("================================================================\n\n")
  
  for (i in 1:min(10, nrow(top_opportunities))) {
    opp <- top_opportunities[i, ]
    cat(sprintf("%d. %s (%s)\n", i, opp$issuer, opp$issuerTicker))
    cat(sprintf("   Hedging Score: %d/100\n", opp$hedging_score))
    cat(sprintf("   Submanagers: %d (%d buying, %d selling)\n",
                opp$n_submanagers, opp$n_buying, opp$n_selling))
    cat(sprintf("   Position Range: %.2f%% to %.2f%% (spread: %.2f%%)\n",
                opp$min_pct_change, opp$max_pct_change, opp$hedging_magnitude))
    cat(sprintf("   Aggregate Change: %.2f%%\n", opp$agg_pct_change))
    cat(sprintf("   Total Value: $%s\n", format(opp$total_value, big.mark = ",")))
    
    if (abs(opp$agg_pct_change) < 10 & opp$hedging_magnitude > 50) {
      cat("   🔥 SIGNAL: Internal disagreement despite stable aggregate\n")
    } else if (opp$agg_pct_change > 0 & opp$min_pct_change < -15) {
      cat("   📈 SIGNAL: Net buying but one fund aggressively exiting\n")
    } else if (opp$agg_pct_change < 0 & opp$max_pct_change > 15) {
      cat("   📉 SIGNAL: Net selling but one fund aggressively buying\n")
    }
    cat("\n")
  }
  
  if (export_csv) {
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    output_file <- here::here("data", "processed", 
                              paste0("hedging_scan_", timestamp, ".csv"))
    write.csv(hedging_results, output_file, row.names = FALSE)
    cat(sprintf("✓ Results exported to: %s\n\n", output_file))
  }
  
  cat("================================================================\n")
  cat("SCAN SUMMARY\n")
  cat("================================================================\n\n")
  
  cat(sprintf("Total hedging opportunities: %d\n", nrow(hedging_results)))
  cat(sprintf("High conviction (score >= 75): %d\n",
              sum(hedging_results$hedging_score >= 75)))
  cat(sprintf("Medium conviction (score 50-74): %d\n",
              sum(hedging_results$hedging_score >= 50 & 
                  hedging_results$hedging_score < 75)))
  cat(sprintf("Average hedging magnitude: %.2f%%\n",
              mean(hedging_results$hedging_magnitude)))
  
  return(list(
    summary = top_opportunities,
    detailed = hedging_results,
    timestamp = timestamp
  ))
}

generate_hedging_report <- function(institutional_data, ticker_symbol) {
  cat("\n================================================================\n")
  cat(sprintf("HEDGING REPORT: %s\n", toupper(ticker_symbol)))
  cat("================================================================\n\n")
  
  detail <- get_hedging_detail(institutional_data, ticker_symbol)
  
  if (nrow(detail) == 0) {
    cat(sprintf("No data found for ticker: %s\n", ticker_symbol))
    return(NULL)
  }
  
  cat("SUBMANAGER POSITION BREAKDOWN:\n")
  cat("==============================\n\n")
  print(detail, n = Inf)
  
  cat("\n\nHEDGING ANALYSIS:\n")
  cat("====================\n\n")
  
  n_positions <- nrow(detail)
  n_buying <- sum(detail$pct_change > 0)
  n_selling <- sum(detail$pct_change < 0)
  avg_change <- mean(detail$pct_change, na.rm = TRUE)
  range_change <- max(detail$pct_change, na.rm = TRUE) - min(detail$pct_change, na.rm = TRUE)
  
  cat(sprintf("Submanagers: %d | Buying: %d | Selling: %d\n", n_positions, n_buying, n_selling))
  cat(sprintf("Average change: %.2f%% | Hedging: %.2f%%\n\n", avg_change, range_change))
  
  if (n_buying > 0 & n_selling > 0) {
    cat("🔴 HEDGING DETECTED!\n")
    if (range_change > 50) cat("⚠️  HIGH MAGNITUDE\n")
  }
  
  return(detail)
}
