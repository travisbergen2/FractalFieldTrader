//+------------------------------------------------------------------+
//| FractalFieldTrader_FPF.mq5 - FPF INTEGRATED VERSION               |
//| Combines original FractalFieldTrader logic with FPF regime filter |
//| Version 2.0 with toggleable regime and FPF filtering              |
//+------------------------------------------------------------------+
#property copyright "FractalFieldTrader FPF v2.0"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include "Include\CoherenceMeasure.mqh"
#include "Include\ChronoceptiveFilter.mqh"
#include "Include\ObserverState.mqh"
#include "Include\FPF_StateEngine.mqh"
#include "Include\FPF_TradeLog.mqh"

struct SMarketScore
{
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    double score;
    int direction;
    double phi;
    double s_strength;
    double a_strength;
    double confidence;
    double coherence;
    double alignment;
    double buy_pressure;
    double sell_pressure;
    double greed;
    double fear;
    double ma50;
    double ma200;
    double price;
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// === Risk Management ===
input double RiskPercent = 0.5;
input int MagicNumber = 77777;
input bool TradeEnabled = true;

// === Market Selection ===
input bool Scan_EURUSD = true;
input bool Scan_GBPUSD = true;
input bool Scan_USDJPY = true;
input bool Scan_XAUUSD = true;

// === Timeframe Selection ===
input bool Scan_M15 = true;
input bool Scan_H1 = true;
input bool Scan_H4 = true;

// === Scanning Settings ===
input int ScanIntervalMinutes = 15;

// === Field Thresholds ===
input double InputCoherence = 55.0;     // FROM YOUR WINNING TEST
input double InputAlignment = 53.0;     // FROM YOUR WINNING TEST

// === FPF FILTERS (NEW) ===
input group "=== FPF Regime & State Filters ==="
input bool InpUseRegimeFilter = false;   // Enable regime-based filtering
input bool InpUseFPFFilter = false;      // Enable FPF state filtering
input int InpBaseWindow = 20;            // FPF calculation window
input int InpHalfLife = 10;              // FPF smoothing half-life
input double InpTrapThreshold = 1.0;     // ATR multiplier for trap detection

// === FPF Filter Thresholds ===
input double InpFPF_E_Threshold = 0.3;   // E-axis filter threshold (emotion)
input double InpFPF_N_Threshold = 0.3;   // N-axis filter threshold (narrative)

// === Trade Logging ===
input group "=== FPF Trade Context Logging ==="
input bool InpEnableTradeLog = true;     // Enable trade logging with FPF context
input string InpTradeLogPath = "FractalFieldTrader_FPF_Trades.csv";

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade Trade;
string ActiveSymbol = "";
ENUM_TIMEFRAMES ActiveTimeframe = PERIOD_CURRENT;

CCoherenceMeasure* ActiveField;
CChronoceptiveFilter* ActiveChrono;
CObserverState* ActiveObserver;

// FPF Engine and Logger (NEW)
CFPFStateEngine* FPF_Engine;
CFPFTradeLogger* TradeLogger;

int TotalTrades = 0;
datetime LastScanTime = 0;
double DailyStartBalance = 0;
datetime CurrentDay = 0;

// Track last bar for FPF updates
datetime LastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("╔═══════════════════════════════════════════════════════════╗");
    Print("║  FRACTAL FIELD TRADER v2.0 - FPF INTEGRATED              ║");
    Print("╚═══════════════════════════════════════════════════════════╝");
    Print("  Regime Filter: ", InpUseRegimeFilter ? "ENABLED" : "DISABLED");
    Print("  FPF Filter: ", InpUseFPFFilter ? "ENABLED" : "DISABLED");
    Print("  Trade Logging: ", InpEnableTradeLog ? "ENABLED" : "DISABLED");
    Print("───────────────────────────────────────────────────────────");

    // Print CSV header to Journal (original)
    Print("TRADE_LOG,Time,Symbol,TF,Direction,Price,Phi,S,A,Conf,Coh,Align,Buy,Sell,Diff,Greed,Fear,EmoDiff,MA50,MA200,TrendPct");

    Trade.SetExpertMagicNumber(MagicNumber);

    ActiveField = new CCoherenceMeasure();
    ActiveChrono = new CChronoceptiveFilter();
    ActiveObserver = new CObserverState();

    // Initialize FPF Engine
    FPF_Engine = new CFPFStateEngine();
    if(!FPF_Engine.Init(_Symbol, PERIOD_CURRENT, InpBaseWindow, InpHalfLife, InpTrapThreshold))
    {
        Print("WARNING: FPF Engine initialization failed for ", _Symbol);
        Print("FPF filters will be disabled");
    }
    else
    {
        Print("✅ FPF State Engine initialized");
    }

    // Initialize Trade Logger
    if(InpEnableTradeLog)
    {
        TradeLogger = new CFPFTradeLogger();
        if(TradeLogger.Init(InpTradeLogPath))
        {
            Print("✅ FPF Trade Logger initialized -> ", InpTradeLogPath);
        }
        else
        {
            Print("WARNING: Trade logger initialization failed");
        }
    }

    DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    CurrentDay = TimeCurrent();

    // Create original CSV file
    int file = FileOpen("TradeData.csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
    if(file != INVALID_HANDLE)
    {
        FileWrite(file, "Time", "Symbol", "TF", "Direction", "Price",
                      "Phi", "S", "A", "Conf", "Coh", "Align",
                      "Buy", "Sell", "Diff", "Greed", "Fear", "EmoDiff",
                      "MA50", "MA200", "TrendPct");
        FileClose(file);
        Print("✅ CSV header created");
    }
    else
    {
        Print("ERROR: Cannot create CSV file!");
    }

    Print("───────────────────────────────────────────────────────────");
    Print(">>> LOGGING TO: TradeData.csv");
    Print(">>> FPF TRADES: ", InpTradeLogPath);
    Print("═══════════════════════════════════════════════════════════");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(CheckPointer(ActiveField) == POINTER_DYNAMIC) delete ActiveField;
    if(CheckPointer(ActiveChrono) == POINTER_DYNAMIC) delete ActiveChrono;
    if(CheckPointer(ActiveObserver) == POINTER_DYNAMIC) delete ActiveObserver;

    if(CheckPointer(FPF_Engine) == POINTER_DYNAMIC)
    {
        FPF_Engine.Deinit();
        delete FPF_Engine;
    }

    if(CheckPointer(TradeLogger) == POINTER_DYNAMIC)
    {
        TradeLogger.Close();
        delete TradeLogger;
    }

    Print("═══════════════════════════════════════════════════════════");
    Print("Total Trades Logged: ", TotalTrades);
    Print("System shutdown complete");
    Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
void OnTick()
{
    if(!TradeEnabled) return;

    CheckDailyReset();

    // Update FPF state on new bar
    UpdateFPFState();

    datetime now = TimeCurrent();
    int minutes_since_scan = (int)((now - LastScanTime) / 60);

    if(PositionsTotal() == 0 && minutes_since_scan >= ScanIntervalMinutes)
    {
        ScanAndTrade();
        LastScanTime = now;
    }

    if(PositionsTotal() > 0 && ActiveSymbol != "")
        ManagePosition();
}

//+------------------------------------------------------------------+
//| Update FPF state on new bar                                       |
//+------------------------------------------------------------------+
void UpdateFPFState()
{
    if(!InpUseRegimeFilter && !InpUseFPFFilter) return;
    if(CheckPointer(FPF_Engine) == POINTER_INVALID) return;

    datetime current_bar = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(current_bar != LastBarTime)
    {
        LastBarTime = current_bar;

        // Calculate FPF state
        FPF_Engine.CalculateState();
        FPF_Engine.UpdateRotationMetrics();

        // Optional: print FPF state for debugging
        /*
        Print("FPF State - P:", DoubleToString(FPF_Engine.GetP(), 3),
              " E:", DoubleToString(FPF_Engine.GetE(), 3),
              " N:", DoubleToString(FPF_Engine.GetN(), 3),
              " A:", DoubleToString(FPF_Engine.GetA(), 3),
              " C:", DoubleToString(FPF_Engine.GetC(), 3),
              " Regime:", FPF_Engine.GetRegimeString());
        */
    }
}

//+------------------------------------------------------------------+
//| Check if trade passes FPF filters                                |
//+------------------------------------------------------------------+
bool PassesFPFFilters(int direction)
{
    if(CheckPointer(FPF_Engine) == POINTER_INVALID)
        return true;  // No filter if engine not initialized

    // Regime filter
    if(InpUseRegimeFilter)
    {
        MarketRegime regime = FPF_Engine.GetRegime();

        // Never trade in CHOP or NONE regimes
        if(regime == REGIME_CHOP || regime == REGIME_NONE)
        {
            Print("  ⛔ Regime filter: CHOP/NONE - trade blocked");
            return false;
        }

        // Long trades: only in TREND_UP or REVERSAL_UP
        if(direction == 1)  // LONG
        {
            if(regime != REGIME_TREND_UP && regime != REGIME_REVERSAL_UP)
            {
                Print("  ⛔ Regime filter: Not in uptrend/reversal_up - long blocked");
                return false;
            }
        }

        // Short trades: only in TREND_DOWN or REVERSAL_DOWN
        if(direction == -1)  // SHORT
        {
            if(regime != REGIME_TREND_DOWN && regime != REGIME_REVERSAL_DOWN)
            {
                Print("  ⛔ Regime filter: Not in downtrend/reversal_down - short blocked");
                return false;
            }
        }
    }

    // FPF state filter
    if(InpUseFPFFilter)
    {
        double E = FPF_Engine.GetE();
        double N = FPF_Engine.GetN();

        // Long trades: block if E or N are too bearish
        if(direction == 1)  // LONG
        {
            if(E < -InpFPF_E_Threshold)
            {
                Print("  ⛔ FPF filter: E too bearish (", DoubleToString(E, 3), ") - long blocked");
                return false;
            }

            if(N < -InpFPF_N_Threshold)
            {
                Print("  ⛔ FPF filter: N too bearish (", DoubleToString(N, 3), ") - long blocked");
                return false;
            }
        }

        // Short trades: block if E or N are too bullish
        if(direction == -1)  // SHORT
        {
            if(E > InpFPF_E_Threshold)
            {
                Print("  ⛔ FPF filter: E too bullish (", DoubleToString(E, 3), ") - short blocked");
                return false;
            }

            if(N > InpFPF_N_Threshold)
            {
                Print("  ⛔ FPF filter: N too bullish (", DoubleToString(N, 3), ") - short blocked");
                return false;
            }
        }
    }

    return true;  // Passed all filters
}

//+------------------------------------------------------------------+
void LogTradeEntry(SMarketScore &opp, double entry_price)
{
    double trend_pct = (opp.ma50 - opp.ma200) / opp.ma200 * 100.0;

    // Print in CSV format to Journal (original)
    string log_line = StringFormat("TRADE_LOG,%s,%s,%s,%s,%.5f,%.4f,%.4f,%.4f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.5f,%.5f,%.3f",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
            opp.symbol,
            EnumToString(opp.timeframe),
            opp.direction == 1 ? "LONG" : "SHORT",
            entry_price,
            opp.phi,
            opp.s_strength,
            opp.a_strength,
            opp.confidence,
            opp.coherence,
            opp.alignment,
            opp.buy_pressure,
            opp.sell_pressure,
            opp.buy_pressure - opp.sell_pressure,
            opp.greed,
            opp.fear,
            MathAbs(opp.greed - opp.fear),
            opp.ma50,
            opp.ma200,
            trend_pct
    );

    Print(log_line);
}

//+------------------------------------------------------------------+
void ScanAndTrade()
{
    Print("═══════════════════════════════════════════════════════════");
    Print("SCANNING MARKETS...");

    SMarketScore scores[];
    ArrayResize(scores, 0);

    if(Scan_EURUSD)
    {
        if(Scan_M15) AddScore(scores, "EURUSD", PERIOD_M15);
        if(Scan_H1) AddScore(scores, "EURUSD", PERIOD_H1);
        if(Scan_H4) AddScore(scores, "EURUSD", PERIOD_H4);
    }

    if(Scan_GBPUSD)
    {
        if(Scan_M15) AddScore(scores, "GBPUSD", PERIOD_M15);
        if(Scan_H1) AddScore(scores, "GBPUSD", PERIOD_H1);
        if(Scan_H4) AddScore(scores, "GBPUSD", PERIOD_H4);
    }

    if(Scan_USDJPY)
    {
        if(Scan_M15) AddScore(scores, "USDJPY", PERIOD_M15);
        if(Scan_H1) AddScore(scores, "USDJPY", PERIOD_H1);
        if(Scan_H4) AddScore(scores, "USDJPY", PERIOD_H4);
    }

    if(Scan_XAUUSD)
    {
        if(Scan_M15) AddScore(scores, "XAUUSD", PERIOD_M15);
        if(Scan_H1) AddScore(scores, "XAUUSD", PERIOD_H1);
        if(Scan_H4) AddScore(scores, "XAUUSD", PERIOD_H4);
    }

    if(ArraySize(scores) == 0)
    {
        Print("  ⚠️  No valid opportunities");
        return;
    }

    int best_idx = 0;
    double best_score = scores[0].score;

    for(int i = 1; i < ArraySize(scores); i++)
    {
        if(scores[i].score > best_score)
        {
            best_score = scores[i].score;
            best_idx = i;
        }
    }

    SMarketScore best = scores[best_idx];

    Print("═══════════════════════════════════════════════════════════");
    Print("BEST: ", best.symbol, " ", EnumToString(best.timeframe));
    Print("Score: ", DoubleToString(best.score, 3), " | Dir: ", best.direction > 0 ? "LONG" : "SHORT");
    Print("═══════════════════════════════════════════════════════════");

    // Check FPF filters before trading
    if(!PassesFPFFilters(best.direction))
    {
        Print("  ⛔ Trade blocked by FPF filters");
        return;
    }

    if(!ActiveField.Init(best.symbol, best.timeframe))
    {
        Print("ERROR: Cannot init ", best.symbol);
        return;
    }

    ActiveSymbol = best.symbol;
    ActiveTimeframe = best.timeframe;

    // Re-initialize FPF engine for the trading symbol if needed
    if(CheckPointer(FPF_Engine) != POINTER_INVALID && best.symbol != _Symbol)
    {
        FPF_Engine.Deinit();
        if(!FPF_Engine.Init(best.symbol, best.timeframe, InpBaseWindow, InpHalfLife, InpTrapThreshold))
        {
            Print("WARNING: Could not re-init FPF for ", best.symbol);
        }
        else
        {
            // Recalculate state for new symbol
            FPF_Engine.CalculateState();
            FPF_Engine.UpdateRotationMetrics();
        }
    }

    if(best.direction > 0)
        OpenLong(best);
    else
        OpenShort(best);
}

//+------------------------------------------------------------------+
void AddScore(SMarketScore &scores[], string symbol, ENUM_TIMEFRAMES tf)
{
    CCoherenceMeasure temp_field;
    if(!temp_field.Init(symbol, tf)) return;

    temp_field.Calculate();

    double coh = temp_field.GetOverallCoherence();
    double align = temp_field.GetFieldAlignment();

    if(coh < InputCoherence || align < InputAlignment) return;

    CIntentionalState* intent = temp_field.GetIntentionalEngine();
    if(CheckPointer(intent) == POINTER_INVALID) return;

    double buy = intent.GetBuyPressure();
    double sell = intent.GetSellPressure();

    CEmotionalState* emo = temp_field.GetEmotionalEngine();
    if(CheckPointer(emo) == POINTER_INVALID) return;

    double greed = emo.GetGreedLevel();
    double fear = emo.GetFearLevel();

    CObserverState temp_obs;
    temp_obs.Update(coh, align, buy, sell);
    double confidence = temp_obs.GetConfidence();

    CChronoceptiveFilter temp_chrono;
    temp_chrono.ComputeSAMatrices(&temp_field, coh, align, buy, sell);
    double s = temp_chrono.GetSStrength();
    double a = temp_chrono.GetAStrength();

    if(s < 0.12 || confidence < 0.40) return;

    double phi = (s * confidence) + (a * confidence * 0.3);

    double ma_fast[], ma_slow[];
    ArraySetAsSeries(ma_fast, true);
    ArraySetAsSeries(ma_slow, true);

    int ma50 = iMA(symbol, tf, 50, 0, MODE_EMA, PRICE_CLOSE);
    int ma200 = iMA(symbol, tf, 200, 0, MODE_EMA, PRICE_CLOSE);

    if(CopyBuffer(ma50, 0, 0, 1, ma_fast) < 1 ||
       CopyBuffer(ma200, 0, 0, 1, ma_slow) < 1)
    {
        IndicatorRelease(ma50);
        IndicatorRelease(ma200);
        return;
    }

    double price = iClose(symbol, tf, 0);
    bool strong_down = (ma_fast[0] < ma_slow[0]) && (price < ma_fast[0]);
    bool strong_up = (ma_fast[0] > ma_slow[0]) && (price > ma_fast[0]);

    IndicatorRelease(ma50);
    IndicatorRelease(ma200);

    SMarketScore sc;
    sc.symbol = symbol;
    sc.timeframe = tf;
    sc.phi = phi;
    sc.s_strength = s;
    sc.a_strength = a;
    sc.confidence = confidence;
    sc.coherence = coh;
    sc.alignment = align;
    sc.buy_pressure = buy;
    sc.sell_pressure = sell;
    sc.greed = greed;
    sc.fear = fear;
    sc.ma50 = ma_fast[0];
    sc.ma200 = ma_slow[0];
    sc.price = price;

    if(buy > sell + 10 && !strong_down && greed > 50 && fear < 50)
    {
        sc.direction = 1;
        sc.score = phi * confidence * (buy - sell) / 100.0;

        int idx = ArraySize(scores);
        ArrayResize(scores, idx + 1);
        scores[idx] = sc;

        Print("  ✅ ", symbol, " ", EnumToString(tf), " LONG: ", DoubleToString(sc.score, 2));
    }
    else if(sell > buy + 10 && !strong_up && fear > 40 && fear < 80)
    {
        sc.direction = -1;
        sc.score = phi * confidence * (sell - buy) / 100.0;

        int idx = ArraySize(scores);
        ArrayResize(scores, idx + 1);
        scores[idx] = sc;

        Print("  ✅ ", symbol, " ", EnumToString(tf), " SHORT: ", DoubleToString(sc.score, 2));
    }
}

//+------------------------------------------------------------------+
void OpenLong(SMarketScore &opp)
{
    double ask = SymbolInfoDouble(opp.symbol, SYMBOL_ASK);

    int atr_h = iATR(opp.symbol, opp.timeframe, 14);
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atr_h, 0, 0, 1, atr) < 1)
    {
        IndicatorRelease(atr_h);
        return;
    }

    double stop_dist = atr[0] * 2.0;
    double sl = ask - stop_dist;
    double tp = ask + (stop_dist * 3.0);

    double lots = CalcLots(opp.symbol, stop_dist);

    if(Trade.Buy(lots, opp.symbol, ask, sl, tp, "FPF Long"))
    {
        ulong ticket = Trade.ResultOrder();
        Print("✅ LONG OPENED: ", lots, " lots @ ", ask, " | Ticket: ", ticket);

        LogTradeEntry(opp, ask);

        // Cache FPF context for this trade
        if(InpEnableTradeLog && CheckPointer(TradeLogger) != POINTER_INVALID)
        {
            TradeLogger.CacheEntryContext(ticket, TimeCurrent(), opp.symbol,
                                          opp.timeframe, 1, lots, ask, sl, tp,
                                          FPF_Engine);
        }

        TotalTrades++;
    }

    IndicatorRelease(atr_h);
}

//+------------------------------------------------------------------+
void OpenShort(SMarketScore &opp)
{
    double bid = SymbolInfoDouble(opp.symbol, SYMBOL_BID);

    int atr_h = iATR(opp.symbol, opp.timeframe, 14);
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atr_h, 0, 0, 1, atr) < 1)
    {
        IndicatorRelease(atr_h);
        return;
    }

    double stop_dist = atr[0] * 2.0;
    double sl = bid + stop_dist;
    double tp = bid - (stop_dist * 3.0);

    double lots = CalcLots(opp.symbol, stop_dist);

    if(Trade.Sell(lots, opp.symbol, bid, sl, tp, "FPF Short"))
    {
        ulong ticket = Trade.ResultOrder();
        Print("✅ SHORT OPENED: ", lots, " lots @ ", bid, " | Ticket: ", ticket);

        LogTradeEntry(opp, bid);

        // Cache FPF context for this trade
        if(InpEnableTradeLog && CheckPointer(TradeLogger) != POINTER_INVALID)
        {
            TradeLogger.CacheEntryContext(ticket, TimeCurrent(), opp.symbol,
                                          opp.timeframe, -1, lots, bid, sl, tp,
                                          FPF_Engine);
        }

        TotalTrades++;
    }

    IndicatorRelease(atr_h);
}

//+------------------------------------------------------------------+
double CalcLots(string symbol, double stop_dist)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = balance * (RiskPercent / 100.0);

    double tick_val = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

    if(tick_size == 0 || tick_val == 0)
        return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

    double lots = risk / (stop_dist / tick_size * tick_val);

    double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    lots = MathFloor(lots / step) * step;
    return MathMax(min_lot, lots);
}

//+------------------------------------------------------------------+
void ManagePosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        double pl = PositionGetDouble(POSITION_PROFIT);

        if(pl < -1500.0)
        {
            // Get exit info before closing
            datetime close_time = TimeCurrent();
            double exit_price = PositionGetDouble(POSITION_PRICE_CURRENT);

            Trade.PositionClose(ticket);

            // Log completed trade with FPF context
            if(InpEnableTradeLog && CheckPointer(TradeLogger) != POINTER_INVALID)
            {
                TradeLogger.RecordTrade(ticket, close_time, exit_price, pl);
            }

            ActiveSymbol = "";
        }
    }

    // Check if position closed by TP/SL and log it
    if(PositionsTotal() == 0 && ActiveSymbol != "")
    {
        // Position was closed (likely by TP/SL)
        // Note: In real implementation, we'd need to track this better
        // For now, just reset
        ActiveSymbol = "";
    }
}

//+------------------------------------------------------------------+
void CheckDailyReset()
{
    datetime now = TimeCurrent();
    MqlDateTime dt_now, dt_curr;
    TimeToStruct(now, dt_now);
    TimeToStruct(CurrentDay, dt_curr);

    if(dt_now.day != dt_curr.day)
    {
        DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        CurrentDay = now;
    }
}
//+------------------------------------------------------------------+
