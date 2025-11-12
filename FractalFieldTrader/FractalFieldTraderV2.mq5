//+------------------------------------------------------------------+
//| FractalFieldTraderV2.mq5 - ADAPTIVE CHRONOCEPTIVE VERSION        |
//| Now with FPF coupling matrices and ML-based trade gating         |
//+------------------------------------------------------------------+
#property copyright "Fractal Field Trader - FPF ML Edition v11.0"
#property version   "11.00"
#property strict

#include <Trade\Trade.mqh>
#include "Include\CoherenceMeasure.mqh"
#include "Include\ChronoceptiveFilter.mqh"
#include "Include\ChronoceptiveFilterV2.mqh"
#include "Include\ObserverState.mqh"
#include "Include\RegimeAlertManager.mqh"
#include "Include\PhaseCouplingDetector.mqh"
#include "Include\FPF_Engine.mqh"
#include "Include\MLPredictor.mqh"

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

// === FPF Engine (Coupling Matrix S+A) ===
input bool UseFPFEngine = true;             // Use FPF coupling matrix dynamics
input bool LogFPFData = true;               // Log FPF state for ML training

// === ML Trade Gating ===
input bool UseMLGating = true;              // Use ML predictor to gate trades
input double ML_EnterThreshold = 0.75;      // Min probability to enter (75%)
input double ML_StopThreshold = 0.60;       // Stop trading if accuracy < 60%
input int ML_RollingWindow = 20;            // Rolling accuracy window (trades)
input string ML_ModelFile = "fpf_model.txt"; // Model weights file

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
CFPFEngine* FPFEngine;                          // FPF coupling matrix engine
CMLPredictor* MLPredictor;                      // ML-based trade gating

int TotalTrades = 0;
datetime LastScanTime = 0;
double DailyStartBalance = 0;
datetime CurrentDay = 0;

string CurrentRegime = "INITIALIZING";
double CurrentAlpha = 0.1;

// ML tracking
ulong CurrentTradeTicket = 0;
double CurrentTradePrediction = 0.0;
int CurrentTradeDirection = 0;
double CurrentTradeEntryPrice = 0.0;

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
    if(UseFPFEngine)
        header += ",FPF_S_norm,FPF_A_norm,FPF_J_norm,FPF_OrbRatio,FPF_SpotX,FPF_SpotY,FPF_AngVel";
    if(UseMLGating)
        header += ",ML_Prob,ML_Gated";
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

    // Initialize FPF Engine
    if(UseFPFEngine)
    {
        FPFEngine = new CFPFEngine();
        Print("✅ FPF Coupling Matrix Engine initialized");
        Print("   Symmetric (S) + Antisymmetric (A) = J(P)");
        Print("   Rotating spot dynamics enabled");
    }

    // Initialize ML Predictor
    if(UseMLGating)
    {
        MLPredictor = new CMLPredictor();
        MLPredictor.Configure(ML_EnterThreshold, ML_StopThreshold, ML_RollingWindow);
        MLPredictor.LoadModel(ML_ModelFile);
        Print("✅ ML Trade Gating initialized");
        Print("   Enter threshold: ", DoubleToString(ML_EnterThreshold * 100, 0), "%");
        Print("   Stop threshold: ", DoubleToString(ML_StopThreshold * 100, 0), "%");
        Print("   Rolling window: ", ML_RollingWindow, " trades");
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
    if(CheckPointer(FPFEngine) == POINTER_DYNAMIC) delete FPFEngine;
    if(CheckPointer(MLPredictor) == POINTER_DYNAMIC) delete MLPredictor;

    Print("═══════════════════════════════════════════════════════════");
    Print("Total Trades Logged: ", TotalTrades);
    if(EnableCouplingDetector && CheckPointer(CouplingDetector) != POINTER_INVALID)
    {
        Print("Final Coupling Index: ", DoubleToString(CouplingDetector.GetGlobalCouplingIndex(), 3));
        Print("Final Regime: ", CouplingDetector.GetDominantRegime());
    }
    if(UseMLGating && CheckPointer(MLPredictor) != POINTER_INVALID)
    {
        MLPredictor.PrintStats();
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
//| Log trade entry with adaptive and FPF metrics                    |
//+------------------------------------------------------------------+
void LogTradeEntry(SMarketScore &opp, double entry_price, double ml_prob = 0.5)
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

    // Add FPF metrics if enabled
    if(UseFPFEngine && CheckPointer(FPFEngine) != POINTER_INVALID)
    {
        log_line += StringFormat(",%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
                FPFEngine.GetResonanceIntensity(),
                FPFEngine.GetOrbitalIntensity(),
                FPFEngine.GetFieldIntensity(),
                FPFEngine.GetOrbitalRatio(),
                FPFEngine.GetSpotX(),
                FPFEngine.GetSpotY(),
                FPFEngine.GetAngularVelocity()
        );
    }

    // Add ML prediction probability
    if(UseMLGating)
    {
        log_line += StringFormat(",%.4f,YES", ml_prob);
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
//| Open long position with FPF + ML gating                          |
//+------------------------------------------------------------------+
void OpenLong(SMarketScore &opp)
{
    double ask = SymbolInfoDouble(opp.symbol, SYMBOL_ASK);

    // Update FPF state
    if(UseFPFEngine && CheckPointer(FPFEngine) != POINTER_INVALID)
    {
        CTemporalState* temporal = ActiveField.GetTemporalEngine();
        double temporal_coh = (temporal != NULL) ? temporal.Calculate() : opp.coherence;

        FPFEngine.UpdateState(temporal_coh, opp.coherence, opp.confidence * 100,
                             opp.alignment, opp.buy_pressure);
        FPFEngine.GenerateCouplingMatrix();

        if(LogFPFData)
            FPFEngine.PrintDiagnostics();
    }

    // ML Gating - check prediction probability
    double ml_prob = 0.5;
    bool ml_approved = true;

    if(UseMLGating && CheckPointer(MLPredictor) != POINTER_INVALID)
    {
        double features[];
        if(UseFPFEngine && CheckPointer(FPFEngine) != POINTER_INVALID)
        {
            FPFEngine.GetFeatures(features);
        }
        else
        {
            // Fallback: use traditional features
            ArrayResize(features, 11);
            features[0] = opp.coherence / 100.0;
            features[1] = opp.alignment / 100.0;
            features[2] = opp.confidence;
            features[3] = opp.s_strength;
            features[4] = opp.a_strength;
            features[5] = opp.phi;
            features[6] = (opp.buy_pressure - opp.sell_pressure) / 100.0;
            features[7] = opp.greed / 100.0;
            features[8] = opp.fear / 100.0;
            features[9] = (opp.ma50 - opp.ma200) / opp.ma200;
            features[10] = opp.price / opp.ma50;
        }

        ml_approved = MLPredictor.ShouldEnterTrade(features, 1, ml_prob);

        if(!ml_approved)
        {
            Print("🚫 ML GATING BLOCKED LONG - Probability: ", DoubleToString(ml_prob * 100, 1),
                  "% (threshold: ", DoubleToString(ML_EnterThreshold * 100, 1), "%)");
            return;
        }

        Print("✅ ML GATING APPROVED LONG - Probability: ", DoubleToString(ml_prob * 100, 1), "%");
    }

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
        LogTradeEntry(opp, ask, ml_prob);
        TotalTrades++;

        // Store trade info for outcome tracking
        CurrentTradeTicket = Trade.ResultOrder();
        CurrentTradePrediction = ml_prob;
        CurrentTradeDirection = 1;
        CurrentTradeEntryPrice = ask;
    }

    IndicatorRelease(atr_h);
}

//+------------------------------------------------------------------+
//| Open short position with FPF + ML gating                         |
//+------------------------------------------------------------------+
void OpenShort(SMarketScore &opp)
{
    double bid = SymbolInfoDouble(opp.symbol, SYMBOL_BID);

    // Update FPF state
    if(UseFPFEngine && CheckPointer(FPFEngine) != POINTER_INVALID)
    {
        CTemporalState* temporal = ActiveField.GetTemporalEngine();
        double temporal_coh = (temporal != NULL) ? temporal.Calculate() : opp.coherence;

        FPFEngine.UpdateState(temporal_coh, opp.coherence, opp.confidence * 100,
                             opp.alignment, opp.sell_pressure);
        FPFEngine.GenerateCouplingMatrix();

        if(LogFPFData)
            FPFEngine.PrintDiagnostics();
    }

    // ML Gating - check prediction probability
    double ml_prob = 0.5;
    bool ml_approved = true;

    if(UseMLGating && CheckPointer(MLPredictor) != POINTER_INVALID)
    {
        double features[];
        if(UseFPFEngine && CheckPointer(FPFEngine) != POINTER_INVALID)
        {
            FPFEngine.GetFeatures(features);
        }
        else
        {
            // Fallback: use traditional features
            ArrayResize(features, 11);
            features[0] = opp.coherence / 100.0;
            features[1] = opp.alignment / 100.0;
            features[2] = opp.confidence;
            features[3] = opp.s_strength;
            features[4] = opp.a_strength;
            features[5] = opp.phi;
            features[6] = (opp.sell_pressure - opp.buy_pressure) / 100.0;
            features[7] = opp.greed / 100.0;
            features[8] = opp.fear / 100.0;
            features[9] = (opp.ma50 - opp.ma200) / opp.ma200;
            features[10] = opp.price / opp.ma50;
        }

        ml_approved = MLPredictor.ShouldEnterTrade(features, -1, ml_prob);

        if(!ml_approved)
        {
            Print("🚫 ML GATING BLOCKED SHORT - Probability: ", DoubleToString(ml_prob * 100, 1),
                  "% (threshold: ", DoubleToString(ML_EnterThreshold * 100, 1), "%)");
            return;
        }

        Print("✅ ML GATING APPROVED SHORT - Probability: ", DoubleToString(ml_prob * 100, 1), "%");
    }

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
        LogTradeEntry(opp, bid, ml_prob);
        TotalTrades++;

        // Store trade info for outcome tracking
        CurrentTradeTicket = Trade.ResultOrder();
        CurrentTradePrediction = ml_prob;
        CurrentTradeDirection = -1;
        CurrentTradeEntryPrice = bid;
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
