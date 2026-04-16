//+------------------------------------------------------------------+
//|                                                     FREEDOM_EA   |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#property copyright "MK"
#property link "https://www.mql5.com"
#property version "1.0"
#property strict

#include <Trade/Trade.mqh>

#define PriceBufforSize 250
#define PriceBufforSizeFast 250
#define TickBufforSize 10000

string comment = "FREEDOM";
string Version = "FREEDOM";
string Parameters = "Please set your values";

int MAX_ORDER_ITERATION = 5;
bool K3_FALCON_FX = true;
input string Trade_Comment_desc = "Trades captured by ALGO will be visible with comment below:";
input string Trade_Comment = "FREEDOM";

input double Lot_Size = 1;
input double ATR_SL = 0.75;
input double ATR_TP = 1.75;
input double Max_SL = 10000;

bool CanOpen = true;

input int StartTime_HH = 16;
input int StartTime_MM = 0;
input int EndTime_HH = 22;
input int EndTime_MM = 0;

bool duringWorkingHours = false;

int total;

input int Trade_Reference = 1;
input int Max_Trades_Amount = 5;
input int Max_Spread = 75;
input double FreeMargin = 300.0;
input string Advanced_config = "Additional configuration for advanced users";
input bool TP_Dynamic = true;
input bool Infinite_SL = false;
input bool HalfTP_SL = true;
input bool ConstSL = false;
int Slippage = 2;
input bool use_ATR_size = true;
input double ATR_min_size = 15;
input double ATR_max_size = 75;
bool use_ATR_atrSL = true;
double Min_atrSL = 0.2;
input double DeviationTickDelta = 4.5;
input double avgTickSpaceValue = 1.25;
input double MINspeed15sec = 3;
input double SpeedIncreased = 1.2;
input int LastTickNumber = 90;
input double TickThreshold = 0.55;
input bool RatioATRCheck = true;
input double M1_ATR5vsATR14 = 1.00;
input double M15_ATR5vsATR14 = 1.05;
input double Activated_below = true;
input int Max_Consecutive_Losses = 3;
input int Cooldown_After_Loss_Minutes = 30;
input int Min_Minutes_Between_Trades = 5;
bool OneCandleOnly = true;

CTrade trade;

double priceBuffer[PriceBufforSize];
int bufferIndex = 0;
int bufferCount = 0;
double avgTickSpace = 0;
datetime tickTimeBuffer[TickBufforSize];
int tickBufferIndex = 0;
int tickBufferCount = 0;
double speedTick15Sec = 0;
double speedTick5Sec = 0;
double speedTickPrev5Sec = 0;
double tickBuffer[];
int bufferSize = 0;
double upRatio = 0;
double downRatio = 0;
double lastM1Open = 0;
bool IsNewM1Candle = false;
double currentM1Open = 0;
double priceBufferFast[PriceBufforSizeFast];
int bufferIndexFast = 0;
int bufferCountFast = 0;
double fastTickSpace = 0;

int DayCurrent;
int amountOfTrades = 0;
double MarketPoint_size = 0.0;
double MarketLot_size = 0.0;
int consecutiveLosses = 0;
datetime cooldownUntil = 0;
datetime lastTradeOpenTime = 0;
datetime lastHistoryCloseTime = 0;

int CurrentDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.day;
}

int CurrentHour()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour;
}

int CurrentMinute()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.min;
}

double GetBid()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

double GetAsk()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

double GetATR(ENUM_TIMEFRAMES tf, int period, int shift)
{
   int handle = iATR(_Symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buff[];
   ArraySetAsSeries(buff, true);
   double out = 0.0;
   if(CopyBuffer(handle, 0, shift, 1, buff) == 1)
      out = buff[0];
   IndicatorRelease(handle);
   return out;
}

bool SelectPositionByIndex(const int index)
{
   ulong ticket = PositionGetTicket(index);
   if(ticket == 0)
      return false;
   return PositionSelectByTicket(ticket);
}

bool ModifyPositionSLTP(const ulong ticket, const double sl, const double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = _Symbol;
   req.sl = sl;
   req.tp = tp;
   req.magic = Trade_Reference;

   return OrderSend(req, res);
}

int OnInit()
{
   MarketPoint_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   MarketLot_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   ArrayResize(tickBuffer, LastTickNumber);
   bufferSize = 0;
   DayCurrent = CurrentDay();
   consecutiveLosses = 0;
   cooldownUntil = 0;
   lastTradeOpenTime = 0;
   lastHistoryCloseTime = 0;

   trade.SetExpertMagicNumber((ulong)Trade_Reference);
   trade.SetDeviationInPoints(Slippage);

   Comment("FREEDOM is running !!!");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick()
{
   UpdateClosedTradeStats();

   double atrSL = GetATR(PERIOD_M1, 4, 1);
   double currentPrice = GetBid();
   UpdateAveragePriceChange(currentPrice);
   UpdateDeviation(currentPrice);
   UpdateTickSpeeds();
   UpDownRatio();

   double M1_RatioATR5 = GetATR(PERIOD_M1, 5, 0);
   double M1_RatioATR14 = GetATR(PERIOD_M1, 14, 0);
   double M15_RatioATR5 = GetATR(PERIOD_M15, 5, 1);
   double M15_RatioATR14 = GetATR(PERIOD_M15, 14, 1);
   double M1_ATR5vATR14 = (M1_RatioATR14 > 0.0 ? M1_RatioATR5 / M1_RatioATR14 : 0.0);
   double M15_ATR5vATR14 = (M15_RatioATR14 > 0.0 ? M15_RatioATR5 / M15_RatioATR14 : 0.0);

   Comment(" \nATR_Size:  " + DoubleToString(atrSL, 2) +
           "   ||   M1_ATR5vATR14:  " + DoubleToString(M1_ATR5vATR14, 2) +
           "   ||   M15_ATR5vATR14:  " + DoubleToString(M15_ATR5vATR14, 2) +
           "   ||   TickSpeed15Sec:  " + DoubleToString(speedTick15Sec, 2) +
           "   ||   AvgTickSpace:  " + DoubleToString(avgTickSpace, 4) +
           "   ||   DeviationTickSpace:  " + DoubleToString(fastTickSpace, 4) +
           "   ||   LossStreak:  " + IntegerToString(consecutiveLosses));

   total = PositionsTotal();
   numberOfTotalTrades();

   int currHour = CurrentHour();
   int currMin = CurrentMinute();

   duringWorkingHours = (((currHour > StartTime_HH) || (currHour == StartTime_HH && currMin >= StartTime_MM)) &&
                        ((currHour <= (EndTime_HH - 1)) || (currHour == EndTime_HH && currMin <= EndTime_MM)));

   if(total < Max_Trades_Amount && duringWorkingHours)
   {
      if(!CanOpen && DayCurrent != CurrentDay())
         CanOpen = true;

      if(AccountInfoDouble(ACCOUNT_FREEMARGIN) < FreeMargin)
      {
         CanOpen = false;
         DayCurrent = CurrentDay();
         Print("We have no money. FreeMargin below minimum: ", AccountInfoDouble(ACCOUNT_FREEMARGIN));
      }
      else
      {
         if(CanOpen && (Activated_below && CanOpenNewTrade()))
         {
            if(isFastLong_RSI())
               openLongRC_RSI();
            else if(isFastShort_RSI())
               openShortRC_RSI();
         }
      }
   }

   total = PositionsTotal();
   if(total > 0)
   {
      for(int cnt = total - 1; cnt >= 0; cnt--)
      {
         if(!SelectPositionByIndex(cnt))
            continue;

         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != Trade_Reference)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         long type = PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY)
            modif_Buy();
         else if(type == POSITION_TYPE_SELL)
            modif_Sell();
      }

      if(use_ATR_atrSL)
      {
         double atr = GetATR(PERIOD_M1, 4, 1);
         if(atr * (1 + Min_atrSL) < ATR_min_size)
         {
            int maxIter = 5;
            bool closeStatus = false;
            do
            {
               closeStatus = closeAllWolfsWithHG();
               maxIter--;
            }
            while(maxIter > 0 && !closeStatus);
         }
      }
   }
}

double ClampLotSize(double lots)
{
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep <= 0)
      lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return NormalizeDouble(lots, 2);
}

double CalculateOrderLots()
{
   return ClampLotSize(Lot_Size);
}

void UpdateClosedTradeStats()
{
   if(!HistorySelect(lastHistoryCloseTime > 0 ? lastHistoryCloseTime : 0, TimeCurrent()))
      return;

   int totalDeals = (int)HistoryDealsTotal();
   if(totalDeals <= 0)
      return;

   datetime newestProcessed = lastHistoryCloseTime;

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != Trade_Reference)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      if(closeTime <= lastHistoryCloseTime)
         continue;

      double netProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                         HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                         HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

      if(netProfit < 0)
      {
         consecutiveLosses++;
         if(consecutiveLosses >= Max_Consecutive_Losses)
            cooldownUntil = TimeCurrent() + Cooldown_After_Loss_Minutes * 60;
      }
      else if(netProfit > 0)
      {
         consecutiveLosses = 0;
      }

      if(closeTime > newestProcessed)
         newestProcessed = closeTime;
   }

   lastHistoryCloseTime = newestProcessed;
}

bool CanOpenNewTrade()
{
   if(cooldownUntil > TimeCurrent())
      return false;

   if(lastTradeOpenTime > 0 && (TimeCurrent() - lastTradeOpenTime) < Min_Minutes_Between_Trades * 60)
      return false;

   return true;
}

bool openShortRC_RSI()
{
   bool FREEDOM = false;
   double Ichimoku_SL_value = Ichimoku_SL_SELL();
   if(Ichimoku_SL_value > 0.0 && canOpen_Spread())
   {
      double lotToUse = CalculateOrderLots();
      if(trade.Sell(lotToUse, _Symbol, 0.0, NormalizeDouble(Ichimoku_SL_value, _Digits), 0.0, Trade_Comment))
      {
         Print("Short Sleep Well opened");
         FREEDOM = true;
         IsNewM1Candle = false;
         lastTradeOpenTime = TimeCurrent();
      }
      else
      {
         Print("Cannot open short position : ", GetLastError());
      }
   }
   return FREEDOM;
}

double Ichimoku_SL_SELL()
{
   double atrSL = GetATR(PERIOD_M1, 4, 1);
   double above_Candle_SL = GetAsk() + (ATR_SL * atrSL);
   double check = GetAsk() + (Max_SL * _Point);

   if(above_Candle_SL > 0 && above_Candle_SL < check)
      return above_Candle_SL;
   return check;
}

bool openLongRC_RSI()
{
   bool FREEDOM = false;
   double Ichimoku_SL_value = Ichimoku_SL_BUY();
   if(Ichimoku_SL_value > 0.0 && canOpen_Spread())
   {
      double lotToUse = CalculateOrderLots();
      if(trade.Buy(lotToUse, _Symbol, 0.0, NormalizeDouble(Ichimoku_SL_value, _Digits), 0.0, Trade_Comment))
      {
         Print("Long Sleep Well opened");
         FREEDOM = true;
         IsNewM1Candle = false;
         lastTradeOpenTime = TimeCurrent();
      }
      else
      {
         Print("Cannot open long position : ", GetLastError());
      }
   }
   return FREEDOM;
}

double Ichimoku_SL_BUY()
{
   double atrSL = GetATR(PERIOD_M1, 4, 1);
   double below_Candle_SL = GetBid() - (ATR_SL * atrSL);
   double check = GetBid() - (Max_SL * _Point);

   if(below_Candle_SL > 0 && below_Candle_SL > check)
      return below_Candle_SL;
   return check;
}

bool canOpen_Spread()
{
   long spread_value = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread_value <= Max_Spread);
}

bool isFastLong_RSI()
{
   double atrSL = GetATR(PERIOD_M1, 4, 1);
   double atrM15 = GetATR(PERIOD_M15, 14, 0);
   double M1_RatioATR5 = GetATR(PERIOD_M1, 5, 0);
   double M1_RatioATR14 = GetATR(PERIOD_M1, 14, 0);
   double M15_RatioATR5 = GetATR(PERIOD_M15, 5, 1);
   double M15_RatioATR14 = GetATR(PERIOD_M15, 14, 1);

   double LastLowM15 = iLow(_Symbol, PERIOD_M15, 1);
   double LastHighM15 = iHigh(_Symbol, PERIOD_M15, 1);
   double candleOpen = iOpen(_Symbol, PERIOD_M1, 0);

   bool openBy5MasSignal = false;

   if(speedTickPrev5Sec * SpeedIncreased < speedTick5Sec && speedTick15Sec > MINspeed15sec && amountOfTrades < 1 &&
      (!use_ATR_size || (ATR_min_size < atrSL && ATR_max_size > atrSL)) &&
      (avgTickSpaceValue > avgTickSpace) &&
      (MathAbs(avgTickSpace - fastTickSpace) < DeviationTickDelta) &&
      (!RatioATRCheck || (M1_RatioATR14 > 0 && M1_RatioATR5 / M1_RatioATR14 > M1_ATR5vsATR14)) &&
      (!RatioATRCheck || (M15_RatioATR14 > 0 && M15_RatioATR5 / M15_RatioATR14 > M15_ATR5vsATR14)))
   {
      if(candleOpen != lastM1Open)
      {
         lastM1Open = candleOpen;
         IsNewM1Candle = true;
      }

      if(CanOpen && (!OneCandleOnly || IsNewM1Candle) && (upRatio - 0.1 < TickThreshold))
      {
         if(upRatio > TickThreshold && ((LastHighM15 + 0.1 * atrM15) > candleOpen && (LastLowM15 - 0.1 * atrM15) < candleOpen))
         {
            openBy5MasSignal = true;
            return openBy5MasSignal;
         }
      }
   }

   return openBy5MasSignal;
}

bool isFastShort_RSI()
{
   double atrSL = GetATR(PERIOD_M1, 4, 1);
   double atrM15 = GetATR(PERIOD_M15, 14, 0);
   double M1_RatioATR5 = GetATR(PERIOD_M1, 5, 0);
   double M1_RatioATR14 = GetATR(PERIOD_M1, 14, 0);
   double M15_RatioATR5 = GetATR(PERIOD_M15, 5, 1);
   double M15_RatioATR14 = GetATR(PERIOD_M15, 14, 1);

   double LastLowM15 = iLow(_Symbol, PERIOD_M15, 1);
   double LastHighM15 = iHigh(_Symbol, PERIOD_M15, 1);
   double candleOpen = iOpen(_Symbol, PERIOD_M1, 0);

   bool openBy5MasSignal = false;

   if(speedTickPrev5Sec * SpeedIncreased < speedTick5Sec && speedTick15Sec > MINspeed15sec && amountOfTrades < 1 &&
      (!use_ATR_size || (ATR_min_size < atrSL && ATR_max_size > atrSL)) &&
      (avgTickSpaceValue > avgTickSpace) &&
      (MathAbs(avgTickSpace - fastTickSpace) < DeviationTickDelta) &&
      (!RatioATRCheck || (M1_RatioATR14 > 0 && M1_RatioATR5 / M1_RatioATR14 > M1_ATR5vsATR14)) &&
      (!RatioATRCheck || (M15_RatioATR14 > 0 && M15_RatioATR5 / M15_RatioATR14 > M15_ATR5vsATR14)))
   {
      if(candleOpen != lastM1Open)
      {
         lastM1Open = candleOpen;
         IsNewM1Candle = true;
      }

      if(CanOpen && (!OneCandleOnly || IsNewM1Candle) && (downRatio - 0.1 < TickThreshold))
      {
         if(downRatio > TickThreshold && ((LastHighM15 + 0.1 * atrM15) > candleOpen && (LastLowM15 - 0.1 * atrM15) < candleOpen))
         {
            openBy5MasSignal = true;
            return openBy5MasSignal;
         }
      }
   }

   return openBy5MasSignal;
}

bool closeAllWolfsWithHG()
{
   int totalOpenOrders = PositionsTotal();
   if(totalOpenOrders > 0)
   {
      for(int cnt = totalOpenOrders - 1; cnt >= 0; cnt--)
      {
         if(!SelectPositionByIndex(cnt))
            continue;

         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != Trade_Reference)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         if(!trade.PositionClose(ticket))
            Print("Error closeAll, ", GetLastError());
      }
   }

   int wolfs = 0;
   int totalOpenOrdersCheck = PositionsTotal();
   for(int cnt = 0; cnt < totalOpenOrdersCheck; cnt++)
   {
      if(!SelectPositionByIndex(cnt))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (long)PositionGetInteger(POSITION_MAGIC) == Trade_Reference)
         wolfs++;
   }

   return (wolfs == 0);
}

double getCurrentOpenProfit()
{
   double currentProfitOnOpenTrades = 0.0;

   int totalPositions = PositionsTotal();
   for(int cnt = 0; cnt < totalPositions; cnt++)
   {
      if(!SelectPositionByIndex(cnt))
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      currentProfitOnOpenTrades += (profit + swap);
   }

   return NormalizeDouble(currentProfitOnOpenTrades, _Digits);
}

void modif_Buy()
{
   double atrSL = GetATR(PERIOD_M1, 4, 1);
   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double stopLoss = PositionGetDouble(POSITION_SL);
   double takeProfit = PositionGetDouble(POSITION_TP);

   double halfTPCalc = NormalizeDouble((takeProfit - openPrice) / 2, _Digits);
   double halfTPSLcalc = NormalizeDouble((openPrice - halfTPCalc), _Digits);

   if(takeProfit == 0 && !TP_Dynamic)
      takeProfit = NormalizeDouble(openPrice + atrSL * ATR_TP, _Digits);

   if(TP_Dynamic)
      takeProfit = NormalizeDouble(openPrice + atrSL * ATR_TP, _Digits);

   if(!ConstSL)
   {
      if((!HalfTP_SL && stopLoss < openPrice) || Infinite_SL)
         stopLoss = NormalizeDouble(GetBid() - atrSL * ATR_SL, _Digits);

      if(HalfTP_SL && stopLoss < halfTPSLcalc)
         stopLoss = NormalizeDouble(GetBid() - atrSL * ATR_SL, _Digits);
   }

   double oldSL = PositionGetDouble(POSITION_SL);
   double oldTP = PositionGetDouble(POSITION_TP);

   if(stopLoss - oldSL > 10 * _Point || oldTP == 0)
      ModifyPositionSLTP(ticket, stopLoss, takeProfit);

   if(TP_Dynamic && MathAbs(takeProfit - oldTP) > 10 * _Point)
      ModifyPositionSLTP(ticket, PositionGetDouble(POSITION_SL), takeProfit);
}

void modif_Sell()
{
   double atrSL = GetATR(PERIOD_M1, 4, 1);
   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double stopLoss = PositionGetDouble(POSITION_SL);
   double takeProfit = PositionGetDouble(POSITION_TP);

   double halfTPCalc = NormalizeDouble((openPrice - takeProfit) / 2, _Digits);
   double halfTPSLcalc = NormalizeDouble((openPrice + halfTPCalc), _Digits);

   if(takeProfit == 0 && !TP_Dynamic)
      takeProfit = NormalizeDouble(openPrice - atrSL * ATR_TP, _Digits);

   if(TP_Dynamic)
      takeProfit = NormalizeDouble(openPrice - atrSL * ATR_TP, _Digits);

   if(!ConstSL)
   {
      if((!HalfTP_SL && stopLoss > openPrice) || Infinite_SL)
         stopLoss = NormalizeDouble(GetAsk() + atrSL * ATR_SL, _Digits);

      if(HalfTP_SL && stopLoss > halfTPSLcalc)
         stopLoss = NormalizeDouble(GetAsk() + atrSL * ATR_SL, _Digits);
   }

   double oldSL = PositionGetDouble(POSITION_SL);
   double oldTP = PositionGetDouble(POSITION_TP);

   if(oldSL - stopLoss > 10 * _Point || oldSL == 0 || oldTP == 0)
      ModifyPositionSLTP(ticket, stopLoss, takeProfit);

   if(TP_Dynamic && MathAbs(oldTP - takeProfit) > 10 * _Point)
      ModifyPositionSLTP(ticket, PositionGetDouble(POSITION_SL), takeProfit);
}

void numberOfTotalTrades()
{
   int totalTrades = PositionsTotal();
   amountOfTrades = 0;

   for(int i = 0; i < totalTrades; i++)
   {
      if(!SelectPositionByIndex(i))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (long)PositionGetInteger(POSITION_MAGIC) == Trade_Reference)
         amountOfTrades++;
   }
}

bool tradeBUYSecured()
{
   int totalTrades = PositionsTotal();
   for(int i = 0; i < totalTrades; i++)
   {
      if(!SelectPositionByIndex(i))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Trade_Reference)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(PositionGetDouble(POSITION_PRICE_OPEN) < PositionGetDouble(POSITION_SL))
            return true;
      }
   }
   return false;
}

bool tradeSELLecured()
{
   int totalTrades = PositionsTotal();
   for(int i = 0; i < totalTrades; i++)
   {
      if(!SelectPositionByIndex(i))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Trade_Reference)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         if(PositionGetDouble(POSITION_PRICE_OPEN) > PositionGetDouble(POSITION_SL))
            return true;
      }
   }
   return false;
}

void UpdateAveragePriceChange(double newPrice)
{
   priceBuffer[bufferIndex] = newPrice;
   bufferIndex = (bufferIndex + 1) % PriceBufforSize;
   if(bufferCount < PriceBufforSize)
      bufferCount++;

   if(bufferCount > 1)
   {
      double totalChange = 0;
      for(int i = 1; i < bufferCount; i++)
      {
         int currentIndex = (bufferIndex - i + PriceBufforSize) % PriceBufforSize;
         int previousIndex = (currentIndex - 1 + PriceBufforSize) % PriceBufforSize;
         totalChange += MathAbs(priceBuffer[currentIndex] - priceBuffer[previousIndex]);
      }
      avgTickSpace = totalChange / (bufferCount - 1);
   }
}

void UpdateDeviation(double newPrice)
{
   priceBufferFast[bufferIndexFast] = newPrice;
   bufferIndexFast = (bufferIndexFast + 1) % PriceBufforSizeFast;

   if(bufferCountFast < PriceBufforSizeFast)
      bufferCountFast++;

   if(bufferCountFast > 1)
   {
      double sum = 0;
      double sumSq = 0;

      for(int i = 0; i < bufferCountFast; i++)
      {
         int index = (bufferIndexFast - i - 1 + PriceBufforSizeFast) % PriceBufforSizeFast;
         double price = priceBufferFast[index];
         sum += price;
         sumSq += price * price;
      }

      double mean = sum / bufferCountFast;
      double variance = (sumSq / bufferCountFast) - (mean * mean);
      if(variance < 0)
         variance = 0;
      fastTickSpace = MathSqrt(variance);
   }
}

void UpdateTickSpeeds()
{
   datetime now = TimeCurrent();

   tickTimeBuffer[tickBufferIndex] = now;
   tickBufferIndex = (tickBufferIndex + 1) % TickBufforSize;
   if(tickBufferCount < TickBufforSize)
      tickBufferCount++;

   double count15Sec = 0;
   double count5Sec = 0;
   double countPrev5Sec = 0;

   for(int i = 0; i < tickBufferCount; i++)
   {
      int index = (tickBufferIndex - i - 1 + TickBufforSize) % TickBufforSize;
      int secondsAgo = (int)(now - tickTimeBuffer[index]);

      if(secondsAgo <= 15)
         count15Sec++;
      if(secondsAgo <= 5)
         count5Sec++;
      else if(secondsAgo > 5 && secondsAgo <= 10)
         countPrev5Sec++;

      if(secondsAgo > 15)
         break;
   }

   speedTick15Sec = count15Sec / 15.0;
   speedTick5Sec = count5Sec / 5.0;
   speedTickPrev5Sec = countPrev5Sec / 5.0;
}

void UpDownRatio()
{
   double currentPrice = GetBid();

   for(int i = LastTickNumber - 1; i > 0; i--)
      tickBuffer[i] = tickBuffer[i - 1];
   tickBuffer[0] = currentPrice;

   if(bufferSize < LastTickNumber)
   {
      bufferSize++;
      return;
   }

   int upMoves = 0;
   int downMoves = 0;

   for(int i = 0; i < LastTickNumber - 1; i++)
   {
      if(tickBuffer[i] > tickBuffer[i + 1])
         upMoves++;
      else if(tickBuffer[i] < tickBuffer[i + 1])
         downMoves++;
   }

   double totalMoves = upMoves + downMoves;
   if(totalMoves == 0)
      return;

   upRatio = upMoves / totalMoves;
   downRatio = downMoves / totalMoves;
}