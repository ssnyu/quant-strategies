
# This is a shiny app for simulating a dual EWMA moving average 
# crossover strategy for ETFs.
#
# Just press the "Run App" button on upper right of this panel.
##############################

# Load R packages
library(HighFreq)
library(shiny)
library(dygraphs)
library(zoo)
## Model and data setup

captiont <- paste("Dual EWMA Moving Average Crossover Strategy")

## End setup code


## Create elements of the user interface
uifun <- shiny::fluidPage(
  titlePanel(captiont),

  fluidRow(
    # Input stock symbol
    column(width=2, selectInput("symbol", label="Symbol", choices=rutils::etfenv$symbolv, selected="VTI")),
    # Input add annotations Boolean
    column(width=2, selectInput("add_annotations", label="Add buy/sell annotations?", choices=c("True", "False"), selected="False")),
    # Input the bid-offer spread
    column(width=2, numericInput("bid_offer", label="Bid-offer:", value=0.0000, step=0.0001))
  ),  # end fluidRow

  fluidRow(
    # Input the EWMA decays
    column(width=2, sliderInput("lambdaf", label="Fast lambda:", min=0.8, max=0.99, value=0.9, step=0.001)),
    column(width=2, sliderInput("lambdas", label="Slow lambda:", min=0.8, max=0.99, value=0.95, step=0.001)),
    # Input the trade lag
    column(width=2, sliderInput("lagg", label="lagg", min=1, max=4, value=2, step=1))
  ),  # end fluidRow
  
  # Create output plot panel
  dygraphs::dygraphOutput("dyplot", width="90%", height="550px")

)  # end fluidPage interface


## Define the server code
servfun <- function(input, output) {

  # Create an empty list of reactive values.
  values <- reactiveValues()

  # Load the data
  closep <- shiny::reactive({
    
    symbol <- input$symbol
    cat("Loading data for ", symbol, "\n")
    
    ohlc <- get(symbol, rutils::etfenv)
    quantmod::Cl(ohlc)

  })  # end Load the data
  
  # Load the data
  retv <- shiny::reactive({
    
    cat("Recalculating returns for ", input$symbol, "\n")
    
    rutils::diffit(log(closep()))

  })  # end Load the data
  

  # Recalculate the strategy
  pnls <- shiny::reactive({
    
    cat("Recalculating strategy for ", input$symbol, "\n")
    # Get model parameters from input argument
    closep <- closep()
    lambdaf <- input$lambdaf
    lambdas <- input$lambdas
    # look_back <- input$look_back
    lagg <- input$lagg

    # Calculate cumulative returns
    retv <- retv()
    retc <- cumsum(retv)
    nrows <- NROW(retv)
    
    # Calculate EWMA prices
    ewmaf <- HighFreq::run_mean(closep, lambda=lambdaf)
    ewmas <- HighFreq::run_mean(closep, lambda=lambdas)

    # Determine dates when the EWMAs have crossed
    crossi <- sign(ewmaf - ewmas)
    
    # Calculate cumulative sum of EWMA crossing indicator
    crossc <- HighFreq::roll_sum(tseries=crossi, look_back=lagg)
    crossc[1:lagg] <- 0
    # Calculate the positions
    # Flip position only if the crossi and its recent past values are the same.
    # Otherwise keep previous position.
    # This is designed to prevent whipsaws and over-trading.
    posv <- rep(NA_integer_, nrows)
    posv[1] <- 0
    posv <- ifelse(crossc == lagg, 1, posv)
    posv <- ifelse(crossc == (-lagg), -1, posv)
    posv <- zoo::na.locf(posv, na.rm=FALSE)
    posv[1:lagg] <- 0
    
    # Calculate indicator of flipped positions
    flipi <- rutils::diffit(posv)
    values$ntrades <- sum(abs(flipi)>0)
    
    # Add buy/sell indicators for annotations
    shorti <- (flipi < 0)
    longi <- (flipi > 0)
    
    # Lag the positions to trade in next period
    posv <- rutils::lagit(posv, lagg=1)
    # Calculate strategy pnls
    pnls <- posv*retv
    # Calculate transaction costs
    costs <- 0.5*input$bid_offer*abs(flipi)
    pnls <- (pnls - costs)

    # Scale the pnls so they have same SD as the returns
    pnls <- pnls*sd(retv[retv<0])/sd(pnls[pnls<0])
    
    # Bind together strategy pnls
    pnls <- cbind(retv, pnls)
    
    # Calculate Sharpe ratios
    sharper <- sqrt(252)*sapply(pnls, function(x) mean(x)/sd(x[x<0]))
    values$sharper <- round(sharper, 3)

    # Bind strategy pnls with indicators
    pnls <- cumsum(pnls)
    pnls <- cbind(pnls, retc[longi], retc[shorti])
    colnames(pnls) <- c(paste(input$symbol, "Returns"), "Strategy", "Buy", "Sell")

    pnls

  })  # end Recalculate the strategy
  

  # Plot the cumulative strategy pnls
  output$dyplot <- dygraphs::renderDygraph({
    
    # Get the pnls
    pnls <- pnls()
    colnamev <- colnames(pnls)
    
    # Get Sharpe ratios
    sharper <- values$sharper
    # Get number of trades
    ntrades <- values$ntrades
    
    captiont <- paste("Strategy for", input$symbol, "/ \n", 
        paste0(c("Index SR=", "Strategy SR="), sharper, collapse=" / "), "/ \n",
        "Number of trades=", ntrades)
    
    # Plot with annotations
    add_annotations <- input$add_annotations
    
    # Return to the output argument a dygraph plot with two y-axes
    if (add_annotations == "True") {
      dygraphs::dygraph(pnls, main=captiont) %>%
        dyAxis("y", label=colnamev[1], independentTicks=TRUE) %>%
        dyAxis("y2", label=colnamev[2], independentTicks=TRUE) %>%
        dySeries(name=colnamev[1], axis="y", label=colnamev[1], strokeWidth=1, col="blue") %>%
        dySeries(name=colnamev[2], axis="y2", label=colnamev[2], strokeWidth=1, col="red") %>%
        dySeries(name=colnamev[3], axis="y", label=colnamev[3], drawPoints=TRUE, strokeWidth=0, pointSize=5, col="orange") %>%
        dySeries(name=colnamev[4], axis="y", label=colnamev[4], drawPoints=TRUE, strokeWidth=0, pointSize=5, col="green")
    } else if (add_annotations == "False") {
      dygraphs::dygraph(pnls[, 1:2], main=captiont) %>%
        dyAxis("y", label=colnamev[3], independentTicks=TRUE) %>%
        dyAxis("y2", label=colnamev[2], independentTicks=TRUE) %>%
        dySeries(name=colnamev[1], axis="y", label=colnamev[1], strokeWidth=1, col="blue") %>%
        dySeries(name=colnamev[2], axis="y2", label=colnamev[2], strokeWidth=1, col="red")
    }  # end if
    
  })  # end output plot

}  # end server code

## Return a Shiny app object
shiny::shinyApp(ui=uifun, server=servfun)
