//+------------------------------------------------------------------+
//|                                                     Trump_EA.mq5 |
//|                      v5.0 - Voting System + RR Optimization      |
//|                         Optimized for USDJPY                     |
//+------------------------------------------------------------------+
#property copyright "Trump EA v5.0 - Voting + RR Optimized"
#property link      ""
#property version   "5.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== GENERAL SETTINGS ==="
input int         MagicNumber        = 20250130;         // Magic Number
input double      RiskPercent        = 1.0;              // Risk % per trade
input double      RiskReward         = 3.0;              // Risk:Reward Ratio (3:1)
input int         MaxSpread          = 15;               // Max Spread (1.5 pips USDJPY)
input int         MaxDailyTrades     = 1;                // Max trades per day

input group "=== TRADE WINDOW (UTC) ==="
input int         TradeStartHour     = 7;                // Trade Start (7 UTC = 8h France)
input int         TradeEndHour       = 15;               // Trade End (15 UTC = 16h France)
input bool        UseEndOfDayClose   = true;             // Close positions at 20h (ENABLED - limit losses)
input int         CloseAllHour       = 20;               // Close All Hour (20h UTC)
input bool        CloseFridayEOD     = true;             // Close all Friday 18h (avoid weekend gaps)

input group "=== SIGNAL VOTING SYSTEM ==="
input int         MinSignalVotes     = 1;                // Min Signal Votes Required (1-3)

input group "=== SIGNAL 1: DONCHIAN BREAKOUT ==="
input bool        UseSignal_Donchian = true;             // Use Donchian Breakout Signal
input int         DonchianPeriod     = 20;               // Donchian Period (bars)
input int         ConfirmBars        = 2;                // Confirmation bars (anti-fake)

input group "=== SIGNAL 2: EMA CROSS ==="
input bool        UseSignal_EMACross = true;             // Use EMA Cross Signal
input int         EMA_Fast           = 21;               // EMA Fast Period
input int         EMA_Slow           = 55;               // EMA Slow Period

input group "=== SIGNAL 3: RSI EXTREME ==="
input bool        UseSignal_RSI      = true;             // Use RSI Extreme Signal
input int         RSI_Period         = 14;               // RSI Period
input double      RSI_OversoldBuy    = 35.0;             // RSI Oversold Level (BUY)
input double      RSI_OverboughtSell = 65.0;             // RSI Overbought Level (SELL)

input group "=== FILTER VOTING SYSTEM ==="
input int         MinFilterVotes     = 3;                // Min Filter Votes Required (1-5)

input group "=== FILTER 1: SMMA H4 TREND ==="
input bool        UseFilter_SMMA     = true;             // Use SMMA H4 Filter
input int         SMMA_Period        = 100;              // SMMA Period
input ENUM_TIMEFRAMES TrendTF        = PERIOD_H4;        // Trend Timeframe

input group "=== FILTER 2: ADX STRENGTH ==="
input bool        UseFilter_ADX      = true;             // Use ADX Filter
input int         ADX_Period         = 14;               // ADX Period
input double      ADX_Min            = 20.0;             // ADX Minimum

input group "=== FILTER 3: MACD MOMENTUM ==="
input bool        UseFilter_MACD     = true;             // Use MACD Filter
input int         MACD_Fast          = 12;               // MACD Fast
input int         MACD_Slow          = 26;               // MACD Slow
input int         MACD_Signal        = 9;                // MACD Signal

input group "=== FILTER 4: ATR VOLATILITY ==="
input bool        UseFilter_ATR      = true;             // Use ATR Filter
input int         ATR_Period         = 14;               // ATR Period
input double      ATR_Min_Pips       = 15.0;             // Min ATR (pips)
input double      ATR_Max_Pips       = 100.0;            // Max ATR (pips)

input group "=== FILTER 5: RSI EXTREME AVOID ==="
input bool        UseFilter_RSI_Extreme = true;          // Avoid RSI Extreme Zones
input double      RSI_AvoidBuyAbove  = 80.0;             // Avoid BUY if RSI > 80
input double      RSI_AvoidSellBelow = 20.0;             // Avoid SELL if RSI < 20

input group "=== RR OPTIMIZATION ==="
input bool        UseTrailingStop    = false;            // Use Trailing Stop (DISABLED - let TP hit)
input double      TrailStartRR       = 1.0;              // Start trailing at X:1 RR
input double      TrailATR_Mult      = 1.0;              // Trailing distance (ATR mult)
input bool        MoveToBreakeven    = false;            // Move SL to breakeven (DISABLED - pure 3:1)

input group "=== STOP LOSS ==="
input double      SL_ATR_Mult        = 1.0;              // Stop Loss ATR Multiplier (tighter = TP more reachable)
input ENUM_TIMEFRAMES SignalTF       = PERIOD_H1;        // Signal Timeframe

input group "=== HARD LIMITS (Safety Net) ==="
input bool        UseHardLimits      = true;             // Use Hard $ Limits
input double      MaxLossPerTrade    = 100.0;            // Max Loss $ per trade (HARD STOP)
input double      MaxProfitPerTrade  = 300.0;            // Max Profit $ per trade (HARD TP)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symbolInfo;

// Indicator handles
int hSMMA;
int hADX;
int hMACD;
int hATR;
int hEMA_Fast, hEMA_Slow;
int hRSI;

// Daily tracking
datetime LastDayReset = 0;
int    DailyTradeCount = 0;
datetime LastBarTime = 0;

// Position management
bool BreakevenSet = false;

// Pip value
double PipValue = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   if(!symbolInfo.Name(_Symbol))
   {
      Print("ERROR: Failed to initialize symbol info");
      return INIT_FAILED;
   }

   int digits = symbolInfo.Digits();
   if(digits == 3 || digits == 2)
      PipValue = symbolInfo.Point() * 10;
   else
      PipValue = symbolInfo.Point() * 10;

   // Create indicator handles
   hSMMA = iMA(_Symbol, TrendTF, SMMA_Period, 0, MODE_SMMA, PRICE_CLOSE);
   hADX = iADX(_Symbol, SignalTF, ADX_Period);
   hMACD = iMACD(_Symbol, SignalTF, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   hATR = iATR(_Symbol, SignalTF, ATR_Period);
   hEMA_Fast = iMA(_Symbol, SignalTF, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA_Slow = iMA(_Symbol, SignalTF, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, SignalTF, RSI_Period, PRICE_CLOSE);

   if(hSMMA == INVALID_HANDLE || hADX == INVALID_HANDLE ||
      hMACD == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      hEMA_Fast == INVALID_HANDLE || hEMA_Slow == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   Print("==============================================");
   Print("TRUMP EA v5.0 - VOTING SYSTEM + RR OPTIMIZED");
   Print("==============================================");
   Print("Symbol: ", _Symbol);
   Print("SIGNALS: Donchian=", UseSignal_Donchian, " | EMA=", UseSignal_EMACross, " | RSI=", UseSignal_RSI);
   Print("Min Signal Votes: ", MinSignalVotes);
   Print("FILTERS: SMMA=", UseFilter_SMMA, " | ADX=", UseFilter_ADX, " | MACD=", UseFilter_MACD, " | ATR=", UseFilter_ATR);
   Print("Min Filter Votes: ", MinFilterVotes);
   Print("RR: 1:", RiskReward, " | Trailing=", UseTrailingStop, " | Breakeven=", MoveToBreakeven);
   Print("End of Day Close: ", UseEndOfDayClose, " at ", CloseAllHour, "h UTC");
   Print("Friday Close: ", CloseFridayEOD, " at 18h UTC (avoid weekend gaps)");
   Print("HARD LIMITS: ", UseHardLimits, " | Max Loss: -", MaxLossPerTrade, "$ | Max Profit: +", MaxProfitPerTrade, "$");
   Print("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hSMMA != INVALID_HANDLE) IndicatorRelease(hSMMA);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hMACD != INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA_Fast != INVALID_HANDLE) IndicatorRelease(hEMA_Fast);
   if(hEMA_Slow != INVALID_HANDLE) IndicatorRelease(hEMA_Slow);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);

   Print("Trump EA v5.0 deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!symbolInfo.RefreshRates())
      return;

   MqlDateTime timeStruct;
   datetime currentTime = TimeCurrent();
   TimeToStruct(currentTime, timeStruct);
   int currentHour = timeStruct.hour;

   // Daily reset
   datetime dayStart = currentTime - (currentTime % 86400);
   if(dayStart != LastDayReset)
   {
      ResetDailyVariables();
      LastDayReset = dayStart;
   }

   //--- MANAGE EXISTING POSITIONS (Trailing, Breakeven) ---
   ManageOpenPositions();

   //--- CLOSE ALL FRIDAY 18h (avoid weekend gaps) ---
   if(CloseFridayEOD && timeStruct.day_of_week == 5 && currentHour >= 18)
   {
      CloseAllPositions("Friday 18h - Avoid Weekend Gap");
      return;
   }

   //--- CLOSE ALL AT END OF DAY 20h (limit overnight risk) ---
   if(UseEndOfDayClose && currentHour >= CloseAllHour)
   {
      CloseAllPositions("End of Day (20h UTC)");
      return;
   }

   //--- ONLY CHECK ON NEW BAR ---
   datetime currentBarTime = iTime(_Symbol, SignalTF, 0);
   if(currentBarTime == LastBarTime)
      return;
   LastBarTime = currentBarTime;

   //--- CHECK IF WE CAN TRADE ---
   if(!CanTrade(currentHour))
      return;

   //--- CHECK SIGNAL VOTES ---
   int signalDirection = 0;
   int signalVotes = CountSignalVotes(signalDirection);

   if(signalVotes >= MinSignalVotes && signalDirection != 0)
   {
      Print(">>> SIGNAL VOTES: ", signalVotes, "/", MinSignalVotes, " required | Direction: ", (signalDirection == 1 ? "BUY" : "SELL"));

      //--- CHECK FILTER VOTES ---
      int filterVotes = CountFilterVotes(signalDirection);

      if(filterVotes >= MinFilterVotes)
      {
         Print(">>> FILTER VOTES: ", filterVotes, "/", MinFilterVotes, " required - TRADE CONFIRMED");
         ExecuteTrade(signalDirection);
      }
      else
      {
         Print(">>> FILTER VOTES: ", filterVotes, "/", MinFilterVotes, " required - NOT ENOUGH");
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK IF WE CAN TRADE                                             |
//+------------------------------------------------------------------+
bool CanTrade(int currentHour)
{
   int currentSpread = (int)symbolInfo.Spread();
   if(currentSpread > MaxSpread)
   {
      Print(">>> SPREAD TOO HIGH: ", currentSpread, " > ", MaxSpread, " - SIGNAL SKIPPED");
      return false;
   }

   if(DailyTradeCount >= MaxDailyTrades)
      return false;

   if(currentHour < TradeStartHour || currentHour >= TradeEndHour)
      return false;

   if(HasOpenPosition())
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| COUNT SIGNAL VOTES                                                |
//+------------------------------------------------------------------+
int CountSignalVotes(int &direction)
{
   int buyVotes = 0;
   int sellVotes = 0;

   //--- SIGNAL 1: DONCHIAN BREAKOUT ---
   if(UseSignal_Donchian)
   {
      int donchianSignal = CheckDonchianSignal();
      if(donchianSignal == 1) { buyVotes++; Print("   [SIGNAL] Donchian: BUY"); }
      if(donchianSignal == -1) { sellVotes++; Print("   [SIGNAL] Donchian: SELL"); }
   }

   //--- SIGNAL 2: EMA CROSS ---
   if(UseSignal_EMACross)
   {
      int emaSignal = CheckEMACrossSignal();
      if(emaSignal == 1) { buyVotes++; Print("   [SIGNAL] EMA Cross: BUY"); }
      if(emaSignal == -1) { sellVotes++; Print("   [SIGNAL] EMA Cross: SELL"); }
   }

   //--- SIGNAL 3: RSI EXTREME ---
   if(UseSignal_RSI)
   {
      int rsiSignal = CheckRSISignal();
      if(rsiSignal == 1) { buyVotes++; Print("   [SIGNAL] RSI: BUY"); }
      if(rsiSignal == -1) { sellVotes++; Print("   [SIGNAL] RSI: SELL"); }
   }

   // Determine direction based on majority
   if(buyVotes > sellVotes && buyVotes > 0)
   {
      direction = 1;
      return buyVotes;
   }
   else if(sellVotes > buyVotes && sellVotes > 0)
   {
      direction = -1;
      return sellVotes;
   }

   direction = 0;
   return 0;
}

//+------------------------------------------------------------------+
//| COUNT FILTER VOTES                                                |
//+------------------------------------------------------------------+
int CountFilterVotes(int direction)
{
   int votes = 0;

   //--- FILTER 1: SMMA H4 TREND ---
   if(UseFilter_SMMA)
   {
      if(CheckSMMAFilter(direction))
      {
         votes++;
         Print("   [FILTER OK] SMMA H4");
      }
      else
      {
         Print("   [FILTER X] SMMA H4");
      }
   }

   //--- FILTER 2: ADX STRENGTH ---
   if(UseFilter_ADX)
   {
      double adxValue = 0;
      if(CheckADXFilter(adxValue))
      {
         votes++;
         Print("   [FILTER OK] ADX (", DoubleToString(adxValue, 1), ")");
      }
      else
      {
         Print("   [FILTER X] ADX (", DoubleToString(adxValue, 1), ")");
      }
   }

   //--- FILTER 3: MACD MOMENTUM ---
   if(UseFilter_MACD)
   {
      if(CheckMACDFilter(direction))
      {
         votes++;
         Print("   [FILTER OK] MACD");
      }
      else
      {
         Print("   [FILTER X] MACD");
      }
   }

   //--- FILTER 4: ATR VOLATILITY ---
   if(UseFilter_ATR)
   {
      double atrPips = 0;
      if(CheckATRFilter(atrPips))
      {
         votes++;
         Print("   [FILTER OK] ATR (", DoubleToString(atrPips, 1), " pips)");
      }
      else
      {
         Print("   [FILTER X] ATR (", DoubleToString(atrPips, 1), " pips)");
      }
   }

   //--- FILTER 5: RSI EXTREME AVOID ---
   if(UseFilter_RSI_Extreme)
   {
      double rsiValue = 0;
      if(CheckRSIExtremeFilter(direction, rsiValue))
      {
         votes++;
         Print("   [FILTER OK] RSI Not Extreme (", DoubleToString(rsiValue, 1), ")");
      }
      else
      {
         Print("   [FILTER X] RSI EXTREME ZONE (", DoubleToString(rsiValue, 1), ") - AVOID!");
      }
   }

   return votes;
}

//+------------------------------------------------------------------+
//| CHECK DONCHIAN SIGNAL                                             |
//+------------------------------------------------------------------+
int CheckDonchianSignal()
{
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int barsNeeded = DonchianPeriod + ConfirmBars + 2;

   if(CopyHigh(_Symbol, SignalTF, 0, barsNeeded, high) < barsNeeded) return 0;
   if(CopyLow(_Symbol, SignalTF, 0, barsNeeded, low) < barsNeeded) return 0;
   if(CopyClose(_Symbol, SignalTF, 0, barsNeeded, close) < barsNeeded) return 0;

   double donchianHigh = 0;
   double donchianLow = DBL_MAX;

   for(int i = ConfirmBars + 1; i <= DonchianPeriod + ConfirmBars; i++)
   {
      if(high[i] > donchianHigh) donchianHigh = high[i];
      if(low[i] < donchianLow) donchianLow = low[i];
   }

   // Bullish breakout with confirmation
   bool bullishBreakout = true;
   for(int i = 1; i <= ConfirmBars; i++)
   {
      if(close[i] <= donchianHigh) { bullishBreakout = false; break; }
   }
   if(bullishBreakout) return 1;

   // Bearish breakout with confirmation
   bool bearishBreakout = true;
   for(int i = 1; i <= ConfirmBars; i++)
   {
      if(close[i] >= donchianLow) { bearishBreakout = false; break; }
   }
   if(bearishBreakout) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| CHECK EMA CROSS SIGNAL                                            |
//+------------------------------------------------------------------+
int CheckEMACrossSignal()
{
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   if(CopyBuffer(hEMA_Fast, 0, 0, 3, emaFast) < 3) return 0;
   if(CopyBuffer(hEMA_Slow, 0, 0, 3, emaSlow) < 3) return 0;

   // Bullish Cross
   if(emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2])
      return 1;

   // Bearish Cross
   if(emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| CHECK RSI SIGNAL                                                  |
//+------------------------------------------------------------------+
int CheckRSISignal()
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return 0;

   // RSI was oversold and now rising (BUY)
   if(rsi[2] < RSI_OversoldBuy && rsi[1] > rsi[2])
      return 1;

   // RSI was overbought and now falling (SELL)
   if(rsi[2] > RSI_OverboughtSell && rsi[1] < rsi[2])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| CHECK SMMA FILTER                                                 |
//+------------------------------------------------------------------+
bool CheckSMMAFilter(int direction)
{
   double smma[];
   ArraySetAsSeries(smma, true);

   if(CopyBuffer(hSMMA, 0, 0, 1, smma) < 1) return false;

   double price = symbolInfo.Bid();

   if(direction == 1)
      return (price > smma[0]);
   else
      return (price < smma[0]);
}

//+------------------------------------------------------------------+
//| CHECK ADX FILTER                                                  |
//+------------------------------------------------------------------+
bool CheckADXFilter(double &adxValue)
{
   double adx[];
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(hADX, 0, 0, 1, adx) < 1) return false;

   adxValue = adx[0];
   return (adxValue >= ADX_Min);
}

//+------------------------------------------------------------------+
//| CHECK MACD FILTER                                                 |
//+------------------------------------------------------------------+
bool CheckMACDFilter(int direction)
{
   double macdMain[], macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);

   if(CopyBuffer(hMACD, 0, 0, 2, macdMain) < 2) return false;
   if(CopyBuffer(hMACD, 1, 0, 2, macdSignal) < 2) return false;

   if(direction == 1)
      return (macdMain[0] > macdSignal[0]) || (macdMain[0] > macdMain[1]);
   else
      return (macdMain[0] < macdSignal[0]) || (macdMain[0] < macdMain[1]);
}

//+------------------------------------------------------------------+
//| CHECK ATR FILTER                                                  |
//+------------------------------------------------------------------+
bool CheckATRFilter(double &atrPips)
{
   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hATR, 0, 0, 1, atr) < 1) return false;

   atrPips = atr[0] / PipValue;
   return (atrPips >= ATR_Min_Pips && atrPips <= ATR_Max_Pips);
}

//+------------------------------------------------------------------+
//| CHECK RSI EXTREME FILTER (Avoid buying at top, selling at bottom)|
//+------------------------------------------------------------------+
bool CheckRSIExtremeFilter(int direction, double &rsiValue)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(hRSI, 0, 0, 1, rsi) < 1) return false;

   rsiValue = rsi[0];

   // For BUY: RSI must NOT be above 80 (overbought = don't buy)
   if(direction == 1)
      return (rsiValue < RSI_AvoidBuyAbove);

   // For SELL: RSI must NOT be below 20 (oversold = don't sell)
   if(direction == -1)
      return (rsiValue > RSI_AvoidSellBelow);

   return true;
}

//+------------------------------------------------------------------+
//| GET ATR VALUE                                                     |
//+------------------------------------------------------------------+
double GetATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hATR, 0, 0, 1, atr) < 1) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| MANAGE OPEN POSITIONS (Hard Limits + Trailing + Breakeven)        |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
         continue;

      double openPrice = posInfo.PriceOpen();
      double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ?
                            symbolInfo.Bid() : symbolInfo.Ask();
      double sl = posInfo.StopLoss();
      double tp = posInfo.TakeProfit();

      double slDistance = MathAbs(openPrice - sl);
      double currentProfit = (posInfo.PositionType() == POSITION_TYPE_BUY) ?
                             (currentPrice - openPrice) : (openPrice - currentPrice);

      //--- HARD LIMITS: Close if P/L exceeds limits ---
      if(UseHardLimits)
      {
         double currentPL = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();

         // HARD STOP: Close if loss exceeds 100$
         if(currentPL <= -MaxLossPerTrade)
         {
            if(trade.PositionClose(posInfo.Ticket()))
               Print(">>> HARD STOP: Closed at ", DoubleToString(currentPL, 2), "$ (limit: -", MaxLossPerTrade, "$)");
            continue;
         }

         // HARD TP: Close if profit exceeds 300$
         if(currentPL >= MaxProfitPerTrade)
         {
            if(trade.PositionClose(posInfo.Ticket()))
               Print(">>> HARD TP: Closed at +", DoubleToString(currentPL, 2), "$ (limit: +", MaxProfitPerTrade, "$)");
            continue;
         }
      }

      //--- MOVE TO BREAKEVEN AT 1:1 ---
      if(MoveToBreakeven && currentProfit >= slDistance && !BreakevenSet)
      {
         double newSL = openPrice;
         // Add small buffer
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
            newSL += symbolInfo.Spread() * symbolInfo.Point();
         else
            newSL -= symbolInfo.Spread() * symbolInfo.Point();

         if(trade.PositionModify(posInfo.Ticket(), newSL, tp))
         {
            BreakevenSet = true;
            Print(">>> BREAKEVEN SET at ", newSL);
         }
      }

      //--- TRAILING STOP ---
      if(UseTrailingStop && currentProfit >= slDistance * TrailStartRR)
      {
         double atr = GetATR();
         double trailDistance = atr * TrailATR_Mult;
         double newSL;

         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > sl + symbolInfo.Point() * 10)
            {
               if(trade.PositionModify(posInfo.Ticket(), newSL, tp))
                  Print(">>> TRAILING STOP moved to ", newSL);
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(newSL < sl - symbolInfo.Point() * 10)
            {
               if(trade.PositionModify(posInfo.Ticket(), newSL, tp))
                  Print(">>> TRAILING STOP moved to ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   double atr = GetATR();
   if(atr == 0)
   {
      Print("ERROR: Cannot get ATR");
      return;
   }

   double price, sl, tp;
   double slDistance = atr * SL_ATR_Mult;

   if(direction == 1)
   {
      price = symbolInfo.Ask();
      sl = price - slDistance;
      tp = price + (slDistance * RiskReward);
   }
   else
   {
      price = symbolInfo.Bid();
      sl = price + slDistance;
      tp = price - (slDistance * RiskReward);
   }

   double lots = CalculateLotSize(slDistance);
   if(lots <= 0)
   {
      Print("ERROR: Invalid lot size");
      return;
   }

   string comment = "TRUMP_v5";
   bool success = false;

   if(direction == 1)
      success = trade.Buy(lots, _Symbol, price, sl, tp, comment);
   else
      success = trade.Sell(lots, _Symbol, price, sl, tp, comment);

   if(success)
   {
      DailyTradeCount++;
      BreakevenSet = false;  // Reset for new position
      Print("===========================================");
      Print("TRADE EXECUTED: ", (direction == 1 ? "BUY" : "SELL"));
      Print("Lots: ", lots, " | Price: ", price);
      Print("SL: ", sl, " (", DoubleToString(slDistance/PipValue, 1), " pips)");
      Print("TP: ", tp, " (", DoubleToString(slDistance*RiskReward/PipValue, 1), " pips)");
      Print("RR Target: 1:", RiskReward);
      Print("Daily Trades: ", DailyTradeCount, "/", MaxDailyTrades);
      Print("===========================================");
   }
   else
   {
      Print("ERROR: Trade failed - ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopDistance)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);

   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();

   if(tickValue <= 0 || tickSize <= 0 || stopDistance <= 0)
      return 0;

   double stopInTicks = stopDistance / tickSize;
   double lots = riskAmount / (stopInTicks * tickValue);

   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
}

//+------------------------------------------------------------------+
//| HAS OPEN POSITION                                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
         {
            trade.PositionClose(posInfo.Ticket());
            Print("Position CLOSED: ", reason);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| RESET DAILY VARIABLES                                             |
//+------------------------------------------------------------------+
void ResetDailyVariables()
{
   DailyTradeCount = 0;
   BreakevenSet = false;
   Print("=== NEW DAY - VARIABLES RESET ===");
}
//+------------------------------------------------------------------+
