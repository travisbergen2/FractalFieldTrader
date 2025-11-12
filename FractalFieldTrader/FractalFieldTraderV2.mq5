//+------------------------------------------------------------------+
//| FractalFieldTraderV2.mq5 - ADAPTIVE CHRONOCEPTIVE VERSION        |
//| Now with regime detection and dynamic temporal bandwidth         |
//+------------------------------------------------------------------+
#property copyright "Fractal Field Trader - Adaptive v10.0"
#property version   "10.00"
#property strict

#include <Trade\Trade.mqh>
#include "Include\CoherenceMeasure.mqh"
#include "Include\ChronoceptiveFilter.mqh"
#include "Include\ChronoceptiveFilterV2.mqh"
#include "Include\ObserverState.mqh"
#include "Include\RegimeAlertManager.mqh"
#include "Include\PhaseCouplingDetector.mqh"

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

    // NEW: Adaptive metrics
    string regime;
    double alpha;
    double regime_confidence;
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
input double InputCoherence = 45.0;     // Minimum overall coherence (sweet spot: 35-55)
input double InputAlignment = 42.0;     // Minimum field alignment (sweet spot: 35-55)

// === Adaptive Filter ===
input bool UseAdaptiveFilter = true;   // Use adaptive chronoceptive filter (V2)
input bool ShowRegimeAlerts = true;    // Show regime transition alerts
input bool LogAdaptiveMetrics = true;  // Log alpha and regime to CSV

// === Alert System ===
input bool EnableAlerts = true;        // Enable regime alert system
input bool Alert_Journal = true;       // Print to journal log
input bool Alert_File = true;          // Write to alert file
input bool Alert_Popup = false;        // Show popup dialogs
input bool Alert_Sound = true;         // Play alert sounds
input bool Alert_Email = false;        // Send email alerts
input bool Alert_Mobile = false;       // Send mobile notifications
input int CoherenceAlertHigh = 75;     // High coherence alert threshold
input int CoherenceAlertLow = 30;      // Low coherence alert threshold

// === Phase Coupling Detector ===
input bool EnableCouplingDetector = true;   // Track multi-market phase coupling
input int CouplingUpdateMinutes = 5;        // Update coupling analysis every N minutes
input bool ShowCouplingReports = true;      // Print coupling analysis reports

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade Trade;
string ActiveSymbol = "";
ENUM_TIMEFRAMES ActiveTimeframe = PERIOD_CURRENT;

CCoherenceMeasure* ActiveField;
CChronoceptiveFilter* ActiveChronoV1;           // Original filter
CChronoceptiveFilterV2* ActiveChronoV2;         // Adaptive filter
CObserverState* ActiveObserver;
CRegimeAlertManager* AlertManager;              // Alert system
CPhaseCouplingDetector* CouplingDetector;       // Multi-market coupling

int TotalTrades = 0;
datetime LastScanTime = 0;
double DailyStartBalance = 0;
datetime CurrentDay = 0;

string CurrentRegime = "INITIALIZING";
double CurrentAlpha = 0.1;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("╔═══════════════════════════════════════════════════════════╗");
    Print("║  FRACTAL FIELD TRADER V2 - ADAPTIVE CHRONOCEPTION         ║");
    Print("╚═══════════════════════════════════════════════════════════╝");
    Print("  Version: 10.0");
    Print("  Adaptive Filter: ", UseAdaptiveFilter ? "ENABLED" : "DISABLED");
    Print("───────────────────────────────────────────────────────────");

    // Print CSV header to Journal
    string header = "TRADE_LOG,Time,Symbol,TF,Direction,Price,Phi,S,A,Conf,Coh,Align,Buy,Sell,Diff,Greed,Fear,EmoDiff,MA50,MA200,TrendPct";
    if(LogAdaptiveMetrics)
        header += ",Regime,Alpha,RegimeConf";
    Print(header);

    Trade.SetExpertMagicNumber(MagicNumber);

    ActiveField = new CCoherenceMeasure();

    // Initialize appropriate filter version
    if(UseAdaptiveFilter)
    {
        ActiveChronoV2 = new CChronoceptiveFilterV2();
        Print("✅ Adaptive Chronoceptive Filter V2 initialized");
    }
    else
    {
        ActiveChronoV1 = new CChronoceptiveFilter();
        Print("✅ Classic Chronoceptive Filter V1 initialized");
    }

    ActiveObserver = new CObserverState();

    // Initialize alert system
    if(EnableAlerts)
    {
        AlertManager = new CRegimeAlertManager();

        // Configure alert channels
        SAlertConfig alert_config;
        alert_config.AlertJournal = Alert_Journal;
        alert_config.AlertFile = Alert_File;
        alert_config.AlertPopup = Alert_Popup;
        alert_config.AlertSound = Alert_Sound;
        alert_config.AlertEmail = Alert_Email;
        alert_config.AlertMobile = Alert_Mobile;

        // Configure alert triggers
        alert_config.AlertOnRegimeChange = ShowRegimeAlerts;
        alert_config.AlertOnChaosEntry = true;
        alert_config.AlertOnFlowState = true;
        alert_config.AlertOnHighCoherence = true;
        alert_config.AlertOnLowCoherence = true;
        alert_config.AlertOnAttractorShift = true;

        // Set thresholds
        alert_config.HighCoherenceThreshold = CoherenceAlertHigh;
        alert_config.LowCoherenceThreshold = CoherenceAlertLow;

        AlertManager.Configure(alert_config);
        Print("✅ Regime Alert System initialized");
    }

    // Initialize coupling detector
    if(EnableCouplingDetector)
    {
        CouplingDetector = new CPhaseCouplingDetector();
        CouplingDetector.SetUpdateInterval(CouplingUpdateMinutes * 60);
        CouplingDetector.EnableAlerts(ShowCouplingReports, ShowCouplingReports);

        // Add all markets we're scanning
        if(Scan_EURUSD)
        {
            if(Scan_M15) CouplingDetector.AddMarket("EURUSD", PERIOD_M15);
            if(Scan_H1) CouplingDetector.AddMarket("EURUSD", PERIOD_H1);
            if(Scan_H4) CouplingDetector.AddMarket("EURUSD", PERIOD_H4);
        }
        if(Scan_GBPUSD)
        {
            if(Scan_M15) CouplingDetector.AddMarket("GBPUSD", PERIOD_M15);
            if(Scan_H1) CouplingDetector.AddMarket("GBPUSD", PERIOD_H1);
            if(Scan_H4) CouplingDetector.AddMarket("GBPUSD", PERIOD_H4);
        }
        if(Scan_USDJPY)
        {
            if(Scan_M15) CouplingDetector.AddMarket("USDJPY", PERIOD_M15);
            if(Scan_H1) CouplingDetector.AddMarket("USDJPY", PERIOD_H1);
            if(Scan_H4) CouplingDetector.AddMarket("USDJPY", PERIOD_H4);
        }
        if(Scan_XAUUSD)
        {
            if(Scan_M15) CouplingDetector.AddMarket("XAUUSD", PERIOD_M15);
            if(Scan_H1) CouplingDetector.AddMarket("XAUUSD", PERIOD_H1);
            if(Scan_H4) CouplingDetector.AddMarket("XAUUSD", PERIOD_H4);
        }

        Print("✅ Phase Coupling Detector initialized (", CouplingDetector.GetMarketCount(), " markets)");
    }

    DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    CurrentDay = TimeCurrent();

    // Create CSV file with header
    int file = FileOpen("TradeData.csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
    if(file != INVALID_HANDLE)
    {
        if(LogAdaptiveMetrics)
        {
            FileWrite(file, "Time", "Symbol", "TF", "Direction", "Price",
                          "Phi", "S", "A", "Conf", "Coh", "Align",
                          "Buy", "Sell", "Diff", "Greed", "Fear", "EmoDiff",
                          "MA50", "MA200", "TrendPct", "Regime", "Alpha", "RegimeConf");
        }
        else
        {
            FileWrite(file, "Time", "Symbol", "TF", "Direction", "Price",
                          "Phi", "S", "A", "Conf", "Coh", "Align",
                          "Buy", "Sell", "Diff", "Greed", "Fear", "EmoDiff",
                          "MA50", "MA200", "TrendPct");
        }
        FileClose(file);
        Print("✅ CSV file initialized with adaptive metrics");
    }
    else
    {
        Print("❌ ERROR: Cannot create CSV file!");
    }

    Print("───────────────────────────────────────────────────────────");
    Print("✅ SYSTEM READY - Waiting for market opportunities");
    Print("═══════════════════════════════════════════════════════════");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(CheckPointer(ActiveField) == POINTER_DYNAMIC) delete ActiveField;
    if(CheckPointer(ActiveChronoV1) == POINTER_DYNAMIC) delete ActiveChronoV1;
    if(CheckPointer(ActiveChronoV2) == POINTER_DYNAMIC) delete ActiveChronoV2;
    if(CheckPointer(ActiveObserver) == POINTER_DYNAMIC) delete ActiveObserver;
    if(CheckPointer(AlertManager) == POINTER_DYNAMIC) delete AlertManager;
    if(CheckPointer(CouplingDetector) == POINTER_DYNAMIC) delete CouplingDetector;

    Print("═══════════════════════════════════════════════════════════");
    Print("Total Trades Logged: ", TotalTrades);
    if(EnableCouplingDetector && CheckPointer(CouplingDetector) != POINTER_INVALID)
    {
        Print("Final Coupling Index: ", DoubleToString(CouplingDetector.GetGlobalCouplingIndex(), 3));
        Print("Final Regime: ", CouplingDetector.GetDominantRegime());
    }
    Print("System shutdown complete");
    Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!TradeEnabled) return;

    CheckDailyReset();

    // Update coupling detector (it has internal timing control)
    if(EnableCouplingDetector && CheckPointer(CouplingDetector) != POINTER_INVALID)
    {
        CouplingDetector.UpdateAllMarkets();
    }

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
//| Log trade entry with adaptive metrics                            |
//+------------------------------------------------------------------+
void LogTradeEntry(SMarketScore &opp, double entry_price)
{
    double trend_pct = (opp.ma50 - opp.ma200) / opp.ma200 * 100.0;

    // Prepare log line
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

    // Add adaptive metrics if enabled
    if(LogAdaptiveMetrics)
    {
        log_line += StringFormat(",%s,%.4f,%.2f",
                opp.regime,
                opp.alpha,
                opp.regime_confidence
        );
    }

    Print(log_line);

    // Write to CSV file
    int file = FileOpen("TradeData.csv", FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
    if(file != INVALID_HANDLE)
    {
        FileSeek(file, 0, SEEK_END);  // Move to end of file

        if(LogAdaptiveMetrics)
        {
            FileWrite(file,
                     TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                     opp.symbol, EnumToString(opp.timeframe),
                     opp.direction == 1 ? "LONG" : "SHORT",
                     entry_price, opp.phi, opp.s_strength, opp.a_strength,
                     opp.confidence, opp.coherence, opp.alignment,
                     opp.buy_pressure, opp.sell_pressure,
                     opp.buy_pressure - opp.sell_pressure,
                     opp.greed, opp.fear, MathAbs(opp.greed - opp.fear),
                     opp.ma50, opp.ma200, trend_pct,
                     opp.regime, opp.alpha, opp.regime_confidence);
        }
        else
        {
            FileWrite(file,
                     TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                     opp.symbol, EnumToString(opp.timeframe),
                     opp.direction == 1 ? "LONG" : "SHORT",
                     entry_price, opp.phi, opp.s_strength, opp.a_strength,
                     opp.confidence, opp.coherence, opp.alignment,
                     opp.buy_pressure, opp.sell_pressure,
                     opp.buy_pressure - opp.sell_pressure,
                     opp.greed, opp.fear, MathAbs(opp.greed - opp.fear),
                     opp.ma50, opp.ma200, trend_pct);
        }

        FileClose(file);
    }
}

//+------------------------------------------------------------------+
//| Scan markets and execute best opportunity                        |
//+------------------------------------------------------------------+
void ScanAndTrade()
{
    Print("═══════════════════════════════════════════════════════════");
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
        Print("  ⚠️  No valid opportunities found");
        return;
    }

    // Find best score
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
    Print("🎯 BEST OPPORTUNITY: ", best.symbol, " ", EnumToString(best.timeframe));
    Print("  Score: ", DoubleToString(best.score, 3), " | Direction: ", best.direction > 0 ? "LONG" : "SHORT");
    if(UseAdaptiveFilter)
    {
        Print("  Regime: ", best.regime, " (", DoubleToString(best.regime_confidence * 100, 1), "% confidence)");
        Print("  Alpha: ", DoubleToString(best.alpha, 4));
    }
    Print("═══════════════════════════════════════════════════════════");

    // Initialize field for chosen market
    if(!ActiveField.Init(best.symbol, best.timeframe))
    {
        Print("❌ ERROR: Cannot initialize field for ", best.symbol);
        return;
    }

    // Monitor with active field (if alerts enabled)
    if(EnableAlerts && CheckPointer(AlertManager) != POINTER_INVALID && UseAdaptiveFilter)
    {
        // Full monitoring with adaptive filter
        if(CheckPointer(ActiveChronoV2) != POINTER_INVALID)
        {
            CAdaptiveChronoFilter* adaptive = NULL; // Would need to expose this from V2
            // For now, just monitor field state
            AlertManager.MonitorFieldState(ActiveField);
        }
    }

    ActiveSymbol = best.symbol;
    ActiveTimeframe = best.timeframe;

    if(best.direction > 0)
        OpenLong(best);
    else
        OpenShort(best);
}

//+------------------------------------------------------------------+
//| Add market/timeframe score with adaptive metrics                 |
//+------------------------------------------------------------------+
void AddScore(SMarketScore &scores[], string symbol, ENUM_TIMEFRAMES tf)
{
    CCoherenceMeasure temp_field;
    if(!temp_field.Init(symbol, tf)) return;

    temp_field.Calculate();

    double coh = temp_field.GetOverallCoherence();
    double align = temp_field.GetFieldAlignment();

    // Filter by thresholds
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

    // Use appropriate filter version
    double s_strength, a_strength;
    string regime = "UNKNOWN";
    double alpha = 0.1;
    double regime_conf = 0.5;

    if(UseAdaptiveFilter && CheckPointer(ActiveChronoV2) != POINTER_INVALID)
    {
        // Use V2 adaptive filter
        CChronoceptiveFilterV2 temp_chrono;
        temp_chrono.ComputeSAMatrices(&temp_field, coh, align, buy, sell);
        s_strength = temp_chrono.GetSStrength();
        a_strength = temp_chrono.GetAStrength();
        alpha = temp_chrono.GetCurrentAlpha();

        // Get regime (would need to expose from adaptive filter - simplified for now)
        regime = "DETECTING";
        regime_conf = 0.7;

        // Monitor for alerts (if enabled)
        if(EnableAlerts && CheckPointer(AlertManager) != POINTER_INVALID)
        {
            // Note: Would need adaptive filter reference for full monitoring
            // For now, monitor field state directly
            AlertManager.MonitorFieldState(&temp_field);
        }
    }
    else
    {
        // Use V1 classic filter
        CChronoceptiveFilter temp_chrono;
        temp_chrono.ComputeSAMatrices(&temp_field, coh, align, buy, sell);
        s_strength = temp_chrono.GetSStrength();
        a_strength = temp_chrono.GetAStrength();
        regime = "CLASSIC_MODE";
        regime_conf = 1.0;
    }

    // Check minimums - STRICTER to reduce small losses
    if(s_strength < 0.18 || confidence < 0.52) return;

    double phi = (s_strength * confidence) + (a_strength * confidence * 0.3);

    // Get MA data
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

    // Create score struct
    SMarketScore sc;
    sc.symbol = symbol;
    sc.timeframe = tf;
    sc.phi = phi;
    sc.s_strength = s_strength;
    sc.a_strength = a_strength;
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
    sc.regime = regime;
    sc.alpha = alpha;
    sc.regime_confidence = regime_conf;

    // Check direction - STRICTER CONDITIONS to reduce small losses
    // Require larger pressure differential (20 instead of 10) and stronger emotional signals
    if(buy > sell + 20 && !strong_down && greed > 55 && fear < 45 && (greed - fear) > 15)
    {
        sc.direction = 1;  // LONG
        sc.score = phi * confidence * (buy - sell) / 100.0;

        int idx = ArraySize(scores);
        ArrayResize(scores, idx + 1);
        scores[idx] = sc;

        Print("  ✅ ", symbol, " ", EnumToString(tf), " LONG: ", DoubleToString(sc.score, 2));
    }
    else if(sell > buy + 20 && !strong_up && fear > 50 && fear < 75 && greed < 45 && (fear - greed) > 10)
    {
        sc.direction = -1;  // SHORT
        sc.score = phi * confidence * (sell - buy) / 100.0;

        int idx = ArraySize(scores);
        ArrayResize(scores, idx + 1);
        scores[idx] = sc;

        Print("  ✅ ", symbol, " ", EnumToString(tf), " SHORT: ", DoubleToString(sc.score, 2));
    }
}

//+------------------------------------------------------------------+
//| Open long position                                                |
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
        Print("✅ LONG OPENED: ", lots, " lots @ ", ask);
        LogTradeEntry(opp, ask);
        TotalTrades++;
    }

    IndicatorRelease(atr_h);
}

//+------------------------------------------------------------------+
//| Open short position                                               |
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
        Print("✅ SHORT OPENED: ", lots, " lots @ ", bid);
        LogTradeEntry(opp, bid);
        TotalTrades++;
    }

    IndicatorRelease(atr_h);
}

//+------------------------------------------------------------------+
//| Calculate position size                                           |
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
//| Manage open position                                              |
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

        // Emergency exit
        if(pl < -1500.0)
        {
            Trade.PositionClose(ticket);
            ActiveSymbol = "";
        }
    }

    if(PositionsTotal() == 0)
        ActiveSymbol = "";
}

//+------------------------------------------------------------------+
//| Check for daily reset                                             |
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
