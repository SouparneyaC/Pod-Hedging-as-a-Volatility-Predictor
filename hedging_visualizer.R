library(ggplot2)
library(dplyr)
library(tidyr)
library(here)

create_butterfly_chart <- function(institutional_data, ticker_symbol, save_plot = TRUE) {
  ticker_upper <- toupper(ticker_symbol)
  
  positions <- institutional_data %>%
    filter(issuerTicker == ticker_upper, putCall == "", shrsOrPrnAmt > 0) %>%
    mutate(
      old_shares = shrsOrPrnAmt - QOQSshPrnAmt,
      pct_change = ifelse(old_shares != 0, (QOQSshPrnAmt / old_shares) * 100, 0),
      manager = gsub("D\\. E\\. SHAW & CO  L\\.P\\.;?", "", otherManagerName),
      manager = gsub("D\\. E\\. Shaw ", "", manager),
      manager = gsub(" L\\.L\\.C\\.", "", manager),
      manager = ifelse(manager == "", "Main L.P.", manager),
      direction = case_when(
        pct_change > 15 ~ "Strong Buy",
        pct_change > 0 ~ "Buy",
        pct_change < -15 ~ "Strong Sell",
        pct_change < 0 ~ "Sell",
        TRUE ~ "Hold"
      ),
      butterfly_value = pct_change
    ) %>%
    arrange(desc(pct_change))
  
  if (nrow(positions) == 0) {
    cat("No data for", ticker_upper, "\n")
    return(NULL)
  }
  
  company_name <- positions$issuer[1]
  
  p <- ggplot(positions, aes(x = butterfly_value, y = reorder(manager, butterfly_value), fill = direction)) +
    geom_col(width = 0.7) +
    geom_vline(xintercept = 0, color = "gray30", linewidth = 1) +
    scale_fill_manual(
      values = c("Strong Buy" = "#00A36C", "Buy" = "#90EE90", 
                 "Hold" = "#FFD700", "Sell" = "#FFB6C1", "Strong Sell" = "#DC143C"),
      name = "Signal"
    ) +
    labs(
      title = paste0("Submanager Hedging: ", company_name, " (", ticker_upper, ")"),
      subtitle = "Selling ← | → Buying",
      x = "Position Change (%)",
      y = "Submanager"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
      plot.subtitle = element_text(size = 10, hjust = 0.5),
      legend.position = "bottom"
    ) +
    geom_text(aes(label = sprintf("%.1f%%", pct_change),
                  x = ifelse(butterfly_value > 0, butterfly_value + 3, butterfly_value - 3),
                  hjust = ifelse(butterfly_value > 0, 0, 1)),
              size = 3.5, fontface = "bold")
  
  print(p)
  
  if (save_plot) {
    filename <- paste0("output/butterfly_", ticker_upper, ".png")
    ggsave(filename, p, width = 12, height = 8, dpi = 300)
    cat("✓ Chart saved to:", filename, "\n")
  }
  
  return(p)
}
