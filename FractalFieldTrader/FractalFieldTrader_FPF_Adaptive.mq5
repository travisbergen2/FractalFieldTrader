//+------------------------------------------------------------------+
//| FractalFieldTrader_FPF_Adaptive.mq5                               |
//| FPF Integration + Adaptive Risk Management                        |
//| Version 2.1 with dynamic position sizing and regime-based stops  |
//+------------------------------------------------------------------+
#property copyright "FractalFieldTrader FPF Adaptive v2.1"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>
#include "Include\CoherenceMeasure.mqh"
#include "Include\ChronoceptiveFilter.mqh"
#include "Include\ObserverState.mqh"
#include "Include\FPF_StateEngine.mqh"
#include "Include\FPF_TradeLog.mqh"
#include "Include\FPF_RiskManager.mqh"

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

// === Risk Management - BASE ===
input group "=== Base Risk Settings ==="
input double RiskPercent = 0.5;              // Base risk per trade (will be scaled)
input int MagicNumber = 77777;
input bool TradeEnabled = true;

// === ADAPTIVE RISK SETTINGS (NEW!) ===
input group "=== Adaptive Risk Management ==="
input bool UseAdaptiveRisk = true;           // Enable adaptive risk sizing
input double MinRiskPercent = 0.1;           // Minimum risk (safety floor)
input double MaxRiskPercent = 2.0;           // Maximum risk (safety ceiling)

// Confidence scaling
input bool UseConfidenceScaling = true;      // Scale risk by FPF confidence
input double ConfidenceMultiplier = 2.0;     // Max multiplier for high confidence
input double MinConfidenceThreshold = 0.4;   // Below this = reduced risk

// Regime scaling
input bool UseRegimeScaling = true;          // Scale risk by regime type
input double TrendRegimeMultiplier = 1.5;    // Multiply risk in TREND regimes
input double ReversalRegimeMultiplier = 1.0; // Normal risk in REVERSAL
input double ChopRegimeMultiplier = 0.3;     // Reduce risk in CHOP

// Dynamic stops
input bool UseAdaptiveStops = true;          // Adaptive stop loss placement
input double BaseStopATRMultiplier = 2.0;    // Base ATR stop multiplier
input double TrendStopMultiplier = 2.5;      // Wider stops in trends
input double ChopStopMultiplier = 1.5;       // Tighter stops in chop

// Dynamic targets
input bool UseAdaptiveTargets = true;        // Adaptive take profit
input double BaseTargetRMultiple = 3.0;      // Base R-multiple target
input double TrendTargetRMultiple = 4.0;     // Larger targets in trends
input double ReversalTargetRMultiple = 2.5;  // Moderate targets in reversals

// Heat management
input bool UseHeatManagement = true;         // Portfolio heat tracking
input double MaxPortfolioHeat = 6.0;         // Max % of account at risk

// Drawdown protection
input bool UseDrawdownScaling = true;        // Scale down in drawdown
input double DrawdownScaleStart = 5.0;       // Start scaling at 5% DD
input double DrawdownScaleMax = 15.0;        // Stop trading at 15% DD

// === Market Selection ===
input group "=== Market & Timeframe Selection ==="
input bool Scan_EURUSD = true;
input bool Scan_GBPUSD = true;
input bool Scan_USDJPY = true;
input bool Scan_XAUUSD = true;

input bool Scan_M15 = true;
input bool Scan_H1 = true;
input bool Scan_H4 = true;

input int ScanIntervalMinutes = 15;

// === Field Thresholds ===
input group "=== Field Filter Thresholds ==="
input double InputCoherence = 55.0;          // FROM YOUR WINNING TEST
input double InputAlignment = 53.0;          // FROM YOUR WINNING TEST

// === FPF FILTERS ===
input group "=== FPF Regime & State Filters ==="
input bool InpUseRegimeFilter = false;       // Enable regime-based filtering
input bool InpUseFPFFilter = false;          // Enable FPF state filtering
input int InpBaseWindow = 20;                // FPF calculation window
input int InpHalfLife = 10;                  // FPF smoothing half-life
input double InpTrapThreshold = 1.0;         // ATR multiplier for trap detection

input double InpFPF_E_Threshold = 0.3;       // E-axis filter threshold
input double InpFPF_N_Threshold = 0.3;       // N-axis filter threshold

// === Trade Logging ===
input group "=== FPF Trade Context Logging ==="
input bool InpEnableTradeLog = true;
input string InpTradeLogPath = "FPF_Adaptive_Trades.csv";

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade Trade;
string ActiveSymbol = "";
ENUM_TIMEFRAMES ActiveTimeframe = PERIOD_CURRENT;

CCoherenceMeasure* ActiveField;
CChronoceptiveFilter* ActiveChrono;
CObserverState* ActiveObserver;

// FPF Engine, Logger, and Adaptive Risk Manager
CFPFStateEngine* FPF_Engine;
CFPFTradeLogger* TradeLogger;
CFPFRiskManager* RiskManager;  // NEW!

int TotalTrades = 0;
datetime LastScanTime = 0;
double DailyStartBalance = 0;
datetime CurrentDay = 0;
datetime LastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("╔════════════════════════════════════════════════════════════╗");
    Print("║  FRACTAL FIELD TRADER v2.1 - ADAPTIVE RISK                ║");
    Print("╚════════════════════════════════════════════════════════════╝");
    Print("  Adaptive Risk: ", UseAdaptiveRisk ? "ENABLED" : "DISABLED");
    Print("  Regime Filter: ", InpUseRegimeFilter ? "ENABLED" : "DISABLED");
    Print("  FPF Filter: ", InpUseFPFFilter ? "ENABLED" : "DISABLED");
    Print("  Heat Management: ", UseHeatManagement ? "ENABLED" : "DISABLED");
    Print("────────────────────────────────────────────────────────────");

    Trade.SetExpertMagicNumber(MagicNumber);

    ActiveField = new CCoherenceMeasure();
    ActiveChrono = new CChronoceptiveFilter();
    ActiveObserver = new CObserverState();

    // Initialize FPF Engine
    FPF_Engine = new CFPFStateEngine();
    if(!FPF_Engine.Init(_Symbol, PERIOD_CURRENT, InpBaseWindow, InpHalfLife, InpTrapThreshold))
    {
        Print("WARNING: FPF Engine initialization failed");
    }
    else
    {
        Print("✅ FPF State Engine initialized");
    }

    // Initialize Adaptive Risk Manager
    if(UseAdaptiveRisk)
    {
        RiskManager = new CFPFRiskManager();

        SRiskConfig config;
        config.BaseRiskPercent = RiskPercent;
        config.MinRiskPercent = MinRiskPercent;
        config.MaxRiskPercent = MaxRiskPercent;

        config.UseConfidenceScaling = UseConfidenceScaling;
        config.ConfidenceMultiplier = ConfidenceMultiplier;
        config.MinConfidenceThreshold = MinConfidenceThreshold;

        config.UseRegimeScaling = UseRegimeScaling;
        config.TrendRegimeMultiplier = TrendRegimeMultiplier;
        config.ReversalRegimeMultiplier = ReversalRegimeMultiplier;
        config.ChopRegimeMultiplier = ChopRegimeMultiplier;

        config.UseAdaptiveStops = UseAdaptiveStops;
        config.BaseStopATRMultiplier = BaseStopATRMultiplier;
        config.TrendStopMultiplier = TrendStopMultiplier;
        config.ChopStopMultiplier = ChopStopMultiplier;

        config.UseAdaptiveTargets = UseAdaptiveTargets;
        config.BaseTargetRMultiple = BaseTargetRMultiple;
        config.TrendTargetRMultiple = TrendTargetRMultiple;
        config.ReversalTargetRMultiple = ReversalTargetRMultiple;

        config.UseHeatManagement = UseHeatManagement;
        config.MaxPortfolioHeat = MaxPortfolioHeat;

        config.UseDrawdownScaling = UseDrawdownScaling;
        config.DrawdownScaleStart = DrawdownScaleStart;
        config.DrawdownScaleMax = DrawdownScaleMax;

        RiskManager.Init(config);
        Print("✅ Adaptive Risk Manager initialized");
        Print("  Base Risk: ", DoubleToString(RiskPercent, 2), "%");
        Print("  Risk Range: ", DoubleToString(MinRiskPercent, 2), "% - ",
              DoubleToString(MaxRiskPercent, 2), "%");
    }

    // Initialize Trade Logger
    if(InpEnableTradeLog)
    {
        TradeLogger = new CFPFTradeLogger();
        if(TradeLogger.Init(InpTradeLogPath))
        {
            Print("✅ FPF Trade Logger initialized");
        }
    }

    DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    CurrentDay = TimeCurrent();

    // Create original CSV
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

    Print("════════════════════════════════════════════════════════════");
    Print("✅ SYSTEM READY");
    Print("════════════════════════════════════════════════════════════");

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
    if(CheckPointer(RiskManager) == POINTER_DYNAMIC)
    {
        delete RiskManager;
    }

    Print("════════════════════════════════════════════════════════════");
    Print("Total Trades: ", TotalTrades);
    Print("Final Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    if(CheckPointer(RiskManager) != POINTER_INVALID)
    {
        Print("Final Drawdown: ", DoubleToString(RiskManager.GetCurrentDrawdown(), 2), "%");
    }
    Print("════════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
void OnTick()
{
    if(!TradeEnabled) return;

    CheckDailyReset();

    // Update risk manager with current balance
    if(UseAdaptiveRisk && CheckPointer(RiskManager) != POINTER_INVALID)
    {
        RiskManager.UpdateDrawdown();

        // Stop trading if max drawdown hit
        if(UseDrawdownScaling && RiskManager.GetCurrentDrawdown() >= DrawdownScaleMax)
        {
            Print("⛔ MAX DRAWDOWN REACHED - Trading disabled");
            return;
        }
    }

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
void UpdateFPFState()
{
    if(!InpUseRegimeFilter && !InpUseFPFFilter && !UseAdaptiveRisk) return;
    if(CheckPointer(FPF_Engine) == POINTER_INVALID) return;

    datetime current_bar = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(current_bar != LastBarTime)
    {
        LastBarTime = current_bar;
        FPF_Engine.CalculateState();
        FPF_Engine.UpdateRotationMetrics();
    }
}

//+------------------------------------------------------------------+
bool PassesFPFFilters(int direction)
{
    if(CheckPointer(FPF_Engine) == POINTER_INVALID)
        return true;

    // Regime filter
    if(InpUseRegimeFilter)
    {
        MarketRegime regime = FPF_Engine.GetRegime();

        if(regime == REGIME_CHOP || regime == REGIME_NONE)
        {
            Print("  ⛔ Regime filter: CHOP/NONE - blocked");
            return false;
        }

        if(direction == 1 && regime != REGIME_TREND_UP && regime != REGIME_REVERSAL_UP)
        {
            Print("  ⛔ Regime filter: Not uptrend - long blocked");
            return false;
        }

        if(direction == -1 && regime != REGIME_TREND_DOWN && regime != REGIME_REVERSAL_DOWN)
        {
            Print("  ⛔ Regime filter: Not downtrend - short blocked");
            return false;
        }
    }

    // FPF state filter
    if(InpUseFPFFilter)
    {
        double E = FPF_Engine.GetE();
        double N = FPF_Engine.GetN();

        if(direction == 1)
        {
            if(E < -InpFPF_E_Threshold || N < -InpFPF_N_Threshold)
            {
                Print("  ⛔ FPF filter: E/N too bearish - long blocked");
                return false;
            }
        }

        if(direction == -1)
        {
            if(E > InpFPF_E_Threshold || N > InpFPF_N_Threshold)
            {
                Print("  ⛔ FPF filter: E/N too bullish - short blocked");
                return false;
            }
        }
    }

    // Heat management check
    if(UseAdaptiveRisk && UseHeatManagement && CheckPointer(RiskManager) != POINTER_INVALID)
    {
        if(!RiskManager.IsHeatAvailable())
        {
            Print("  ⛔ Portfolio heat limit reached - trade blocked");
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
void LogTradeEntry(SMarketScore &opp, double entry_price)
{
    double trend_pct = (opp.ma50 - opp.ma200) / opp.ma200 * 100.0;

    string log_line = StringFormat("TRADE_LOG,%s,%s,%s,%s,%.5f,%.4f,%.4f,%.4f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.5f,%.5f,%.3f",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
            opp.symbol, EnumToString(opp.timeframe),
            opp.direction == 1 ? "LONG" : "SHORT",
            entry_price, opp.phi, opp.s_strength, opp.a_strength,
            opp.confidence, opp.coherence, opp.alignment,
            opp.buy_pressure, opp.sell_pressure,
            opp.buy_pressure - opp.sell_pressure,
            opp.greed, opp.fear, MathAbs(opp.greed - opp.fear),
            opp.ma50, opp.ma200, trend_pct);

    Print(log_line);
}

//+------------------------------------------------------------------+
void ScanAndTrade()
{
    Print("════════════════════════════════════════════════════════════");
    Print("🔍 SCANNING MARKETS...");

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

    Print("════════════════════════════════════════════════════════════");
    Print("🎯 BEST: ", best.symbol, " ", EnumToString(best.timeframe));
    Print("  Score: ", DoubleToString(best.score, 3), " | Dir: ", best.direction > 0 ? "LONG" : "SHORT");
    Print("════════════════════════════════════════════════════════════");

    if(!PassesFPFFilters(best.direction))
    {
        Print("  ⛔ Trade blocked by filters");
        return;
    }

    if(!ActiveField.Init(best.symbol, best.timeframe))
    {
        Print("❌ ERROR: Cannot init field for ", best.symbol);
        return;
    }

    ActiveSymbol = best.symbol;
    ActiveTimeframe = best.timeframe;

    // Re-init FPF for new symbol if needed
    if(CheckPointer(FPF_Engine) != POINTER_INVALID && best.symbol != _Symbol)
    {
        FPF_Engine.Deinit();
        if(FPF_Engine.Init(best.symbol, best.timeframe, InpBaseWindow, InpHalfLife, InpTrapThreshold))
        {
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

    // Use adaptive risk if enabled
    SRiskResult risk;

    if(UseAdaptiveRisk && CheckPointer(RiskManager) != POINTER_INVALID)
    {
        risk = RiskManager.CalculateRisk(opp.symbol, opp.timeframe, 1, ask, FPF_Engine);

        Print("📊 ADAPTIVE RISK:");
        Print("  Risk%: ", DoubleToString(risk.RiskPercent, 3), "% (", risk.RiskReason, ")");
        Print("  Position: ", DoubleToString(risk.PositionSize, 2), " lots");
        Print("  Stop: ", DoubleToString(risk.StopPrice, 5), " (", DoubleToString(risk.StopDistance / SymbolInfoDouble(opp.symbol, SYMBOL_POINT), 1), " pips)");
        Print("  Target: ", DoubleToString(risk.TargetPrice, 5), " (", DoubleToString(risk.ExpectedR, 1), "R)");
    }
    else
    {
        // Fallback to original fixed risk
        int atr_h = iATR(opp.symbol, opp.timeframe, 14);
        double atr[];
        ArraySetAsSeries(atr, true);

        if(CopyBuffer(atr_h, 0, 0, 1, atr) < 1)
        {
            IndicatorRelease(atr_h);
            return;
        }

        risk.StopDistance = atr[0] * BaseStopATRMultiplier;
        risk.StopPrice = ask - risk.StopDistance;
        risk.TargetPrice = ask + (risk.StopDistance * BaseTargetRMultiple);
        risk.PositionSize = CalcLots(opp.symbol, risk.StopDistance);

        IndicatorRelease(atr_h);
    }

    if(Trade.Buy(risk.PositionSize, opp.symbol, ask, risk.StopPrice, risk.TargetPrice, "FPF Adaptive Long"))
    {
        ulong ticket = Trade.ResultOrder();
        Print("✅ LONG OPENED: ", risk.PositionSize, " lots @ ", ask);

        LogTradeEntry(opp, ask);

        // Cache FPF context
        if(InpEnableTradeLog && CheckPointer(TradeLogger) != POINTER_INVALID)
        {
            TradeLogger.CacheEntryContext(ticket, TimeCurrent(), opp.symbol,
                                          opp.timeframe, 1, risk.PositionSize,
                                          ask, risk.StopPrice, risk.TargetPrice,
                                          FPF_Engine);
        }

        // Add to heat tracker
        if(UseAdaptiveRisk && UseHeatManagement && CheckPointer(RiskManager) != POINTER_INVALID)
        {
            double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * (risk.RiskPercent / 100.0);
            RiskManager.AddOpenRisk(risk_money);
        }

        TotalTrades++;
    }
}

//+------------------------------------------------------------------+
void OpenShort(SMarketScore &opp)
{
    double bid = SymbolInfoDouble(opp.symbol, SYMBOL_BID);

    SRiskResult risk;

    if(UseAdaptiveRisk && CheckPointer(RiskManager) != POINTER_INVALID)
    {
        risk = RiskManager.CalculateRisk(opp.symbol, opp.timeframe, -1, bid, FPF_Engine);

        Print("📊 ADAPTIVE RISK:");
        Print("  Risk%: ", DoubleToString(risk.RiskPercent, 3), "% (", risk.RiskReason, ")");
        Print("  Position: ", DoubleToString(risk.PositionSize, 2), " lots");
        Print("  Stop: ", DoubleToString(risk.StopPrice, 5));
        Print("  Target: ", DoubleToString(risk.TargetPrice, 5), " (", DoubleToString(risk.ExpectedR, 1), "R)");
    }
    else
    {
        int atr_h = iATR(opp.symbol, opp.timeframe, 14);
        double atr[];
        ArraySetAsSeries(atr, true);

        if(CopyBuffer(atr_h, 0, 0, 1, atr) < 1)
        {
            IndicatorRelease(atr_h);
            return;
        }

        risk.StopDistance = atr[0] * BaseStopATRMultiplier;
        risk.StopPrice = bid + risk.StopDistance;
        risk.TargetPrice = bid - (risk.StopDistance * BaseTargetRMultiple);
        risk.PositionSize = CalcLots(opp.symbol, risk.StopDistance);

        IndicatorRelease(atr_h);
    }

    if(Trade.Sell(risk.PositionSize, opp.symbol, bid, risk.StopPrice, risk.TargetPrice, "FPF Adaptive Short"))
    {
        ulong ticket = Trade.ResultOrder();
        Print("✅ SHORT OPENED: ", risk.PositionSize, " lots @ ", bid);

        LogTradeEntry(opp, bid);

        if(InpEnableTradeLog && CheckPointer(TradeLogger) != POINTER_INVALID)
        {
            TradeLogger.CacheEntryContext(ticket, TimeCurrent(), opp.symbol,
                                          opp.timeframe, -1, risk.PositionSize,
                                          bid, risk.StopPrice, risk.TargetPrice,
                                          FPF_Engine);
        }

        if(UseAdaptiveRisk && UseHeatManagement && CheckPointer(RiskManager) != POINTER_INVALID)
        {
            double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * (risk.RiskPercent / 100.0);
            RiskManager.AddOpenRisk(risk_money);
        }

        TotalTrades++;
    }
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
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double risk_dist = MathAbs(open_price - sl);

        if(pl < -1500.0)
        {
            datetime close_time = TimeCurrent();
            double exit_price = PositionGetDouble(POSITION_PRICE_CURRENT);

            Trade.PositionClose(ticket);

            // Log trade
            if(InpEnableTradeLog && CheckPointer(TradeLogger) != POINTER_INVALID)
            {
                TradeLogger.RecordTrade(ticket, close_time, exit_price, pl);
            }

            // Update risk manager
            if(UseAdaptiveRisk && CheckPointer(RiskManager) != POINTER_INVALID)
            {
                RiskManager.RecordLoss();
                if(UseHeatManagement)
                {
                    double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
                    RiskManager.RemoveOpenRisk(risk_money);
                }
            }

            ActiveSymbol = "";
        }
    }

    if(PositionsTotal() == 0 && ActiveSymbol != "")
    {
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
