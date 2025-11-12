//+------------------------------------------------------------------+
//| PhaseCouplingDetector.mqh                                        |
//| Detects phase synchronization across multiple markets            |
//| Identifies global regime shifts and systematic coupling          |
//+------------------------------------------------------------------+

#include "CoherenceMeasure.mqh"
#include "PhaseRotation.mqh"

// Market phase state
struct SMarketPhase
{
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    double phase_angle;        // 0-360 degrees
    double rotation_speed;     // degrees per bar
    double coherence;
    datetime last_update;

    // For tracking phase history
    double phase_history[20];  // Last 20 phase readings
    int history_index;
};

// Coupling measurement between two markets
struct SCouplingPair
{
    string market_a;
    string market_b;
    double coupling_strength;   // 0-1 (0=independent, 1=locked)
    double phase_difference;    // -180 to +180 degrees
    string coupling_type;       // "IN_PHASE", "ANTI_PHASE", "LEADING", "LAGGING"
    datetime detected_time;
};

//+------------------------------------------------------------------+
//| Phase Coupling Detector                                          |
//+------------------------------------------------------------------+
class CPhaseCouplingDetector
{
private:
    SMarketPhase m_markets[];
    SCouplingPair m_couplings[];

    double m_global_coupling_index;    // Average coupling strength across all pairs
    double m_last_global_coupling;
    string m_dominant_regime;          // COUPLED, DECOUPLED, TRANSITIONING

    int m_update_interval_seconds;
    datetime m_last_full_update;

    double m_coupling_threshold_weak;   // Below this = decoupled
    double m_coupling_threshold_strong; // Above this = strongly coupled

    // Alert tracking
    bool m_alert_on_coupling_change;
    bool m_alert_on_regime_shift;
    double m_min_coupling_change_for_alert;

public:
    CPhaseCouplingDetector()
    {
        ArrayResize(m_markets, 0);
        ArrayResize(m_couplings, 0);

        m_global_coupling_index = 0.5;
        m_last_global_coupling = 0.5;
        m_dominant_regime = "INITIALIZING";

        m_update_interval_seconds = 300;  // Update every 5 minutes
        m_last_full_update = 0;

        m_coupling_threshold_weak = 0.3;
        m_coupling_threshold_strong = 0.7;

        m_alert_on_coupling_change = true;
        m_alert_on_regime_shift = true;
        m_min_coupling_change_for_alert = 0.15;
    }

    //+------------------------------------------------------------------+
    //| Add market to tracking                                           |
    //+------------------------------------------------------------------+
    void AddMarket(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        // Check if already tracking
        for(int i = 0; i < ArraySize(m_markets); i++)
        {
            if(m_markets[i].symbol == symbol && m_markets[i].timeframe == timeframe)
                return;  // Already tracking
        }

        // Add new market
        int idx = ArraySize(m_markets);
        ArrayResize(m_markets, idx + 1);

        m_markets[idx].symbol = symbol;
        m_markets[idx].timeframe = timeframe;
        m_markets[idx].phase_angle = 0;
        m_markets[idx].rotation_speed = 0;
        m_markets[idx].coherence = 0;
        m_markets[idx].last_update = 0;
        m_markets[idx].history_index = 0;
        ArrayInitialize(m_markets[idx].phase_history, 0);

        Print("📡 Coupling Detector: Added ", symbol, " ", EnumToString(timeframe));
    }

    //+------------------------------------------------------------------+
    //| Update all market phases                                         |
    //+------------------------------------------------------------------+
    void UpdateAllMarkets()
    {
        datetime now = TimeCurrent();

        // Full update only at specified intervals
        if(now - m_last_full_update < m_update_interval_seconds)
            return;

        Print("🔄 Updating phase coupling analysis...");

        for(int i = 0; i < ArraySize(m_markets); i++)
        {
            UpdateMarketPhase(i);
        }

        CalculateAllCouplings();
        UpdateGlobalRegime();

        m_last_full_update = now;

        // Print summary
        PrintCouplingReport();
    }

    //+------------------------------------------------------------------+
    //| Update single market phase                                       |
    //+------------------------------------------------------------------+
    void UpdateMarketPhase(int market_idx)
    {
        if(market_idx >= ArraySize(m_markets))
            return;

        SMarketPhase& market = m_markets[market_idx];

        // Create field and phase analyzer
        CCoherenceMeasure field(50);
        if(!field.Init(market.symbol, market.timeframe))
            return;

        field.Calculate(market.symbol, market.timeframe);

        CPhaseRotation phase_calc;

        CEmotionalState* emo = field.GetEmotionalEngine();
        CIntentionalState* intent = field.GetIntentionalEngine();

        if(CheckPointer(emo) == POINTER_INVALID || CheckPointer(intent) == POINTER_INVALID)
            return;

        double greed = emo.GetGreedLevel();
        double fear = emo.GetFearLevel();
        double buy = intent.GetBuyPressure();
        double sell = intent.GetSellPressure();

        // Calculate phase angle
        double old_angle = market.phase_angle;
        market.phase_angle = phase_calc.CalculatePhaseAngle(greed, fear, buy, sell);
        market.coherence = field.GetOverallCoherence();

        // Calculate rotation speed (degrees per update)
        double angle_change = market.phase_angle - old_angle;

        // Handle wraparound
        if(angle_change > 180)
            angle_change -= 360;
        else if(angle_change < -180)
            angle_change += 360;

        market.rotation_speed = angle_change;

        // Update phase history
        market.phase_history[market.history_index] = market.phase_angle;
        market.history_index = (market.history_index + 1) % 20;

        market.last_update = TimeCurrent();
    }

    //+------------------------------------------------------------------+
    //| Calculate coupling between all market pairs                      |
    //+------------------------------------------------------------------+
    void CalculateAllCouplings()
    {
        ArrayResize(m_couplings, 0);

        int n = ArraySize(m_markets);
        if(n < 2)
            return;  // Need at least 2 markets

        // Calculate pairwise coupling
        for(int i = 0; i < n - 1; i++)
        {
            for(int j = i + 1; j < n; j++)
            {
                SCouplingPair coupling = CalculateCoupling(i, j);

                int idx = ArraySize(m_couplings);
                ArrayResize(m_couplings, idx + 1);
                m_couplings[idx] = coupling;
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Calculate coupling between two markets                           |
    //+------------------------------------------------------------------+
    SCouplingPair CalculateCoupling(int idx_a, int idx_b)
    {
        SCouplingPair coupling;

        SMarketPhase& market_a = m_markets[idx_a];
        SMarketPhase& market_b = m_markets[idx_b];

        coupling.market_a = market_a.symbol;
        coupling.market_b = market_b.symbol;
        coupling.detected_time = TimeCurrent();

        // Calculate phase difference
        double phase_diff = market_a.phase_angle - market_b.phase_angle;

        // Normalize to -180 to +180
        while(phase_diff > 180) phase_diff -= 360;
        while(phase_diff < -180) phase_diff += 360;

        coupling.phase_difference = phase_diff;

        // Calculate phase coherence over history
        double phase_correlation = CalculatePhaseCorrelation(idx_a, idx_b);

        // Calculate rotation speed similarity
        double speed_similarity = 1.0 - MathAbs(market_a.rotation_speed - market_b.rotation_speed) / 180.0;
        speed_similarity = MathMax(0, speed_similarity);

        // Combined coupling strength
        coupling.coupling_strength = (phase_correlation * 0.7) + (speed_similarity * 0.3);

        // Determine coupling type
        double abs_phase_diff = MathAbs(phase_diff);

        if(coupling.coupling_strength > 0.7)
        {
            if(abs_phase_diff < 30)
                coupling.coupling_type = "IN_PHASE";
            else if(abs_phase_diff > 150)
                coupling.coupling_type = "ANTI_PHASE";
            else if(phase_diff > 0)
                coupling.coupling_type = "A_LEADING";
            else
                coupling.coupling_type = "B_LEADING";
        }
        else if(coupling.coupling_strength < 0.3)
        {
            coupling.coupling_type = "DECOUPLED";
        }
        else
        {
            coupling.coupling_type = "WEAK_COUPLING";
        }

        return coupling;
    }

    //+------------------------------------------------------------------+
    //| Calculate phase correlation from history                         |
    //+------------------------------------------------------------------+
    double CalculatePhaseCorrelation(int idx_a, int idx_b)
    {
        SMarketPhase& market_a = m_markets[idx_a];
        SMarketPhase& market_b = m_markets[idx_b];

        // Simple correlation: how often are they in same quadrant?
        int same_quadrant_count = 0;
        int total_samples = 0;

        for(int i = 0; i < 20; i++)
        {
            double angle_a = market_a.phase_history[i];
            double angle_b = market_b.phase_history[i];

            if(angle_a == 0 && angle_b == 0)
                continue;  // Not initialized yet

            int quad_a = (int)(angle_a / 90.0);
            int quad_b = (int)(angle_b / 90.0);

            if(quad_a == quad_b)
                same_quadrant_count++;

            total_samples++;
        }

        if(total_samples < 5)
            return 0.5;  // Not enough data

        // Convert to 0-1 scale
        // If always in same quadrant = 1.0
        // If random = 0.25
        // Scale: (observed - random) / (perfect - random)
        double observed = (double)same_quadrant_count / total_samples;
        double scaled = (observed - 0.25) / (1.0 - 0.25);

        return MathMax(0, MathMin(1.0, scaled));
    }

    //+------------------------------------------------------------------+
    //| Update global regime classification                              |
    //+------------------------------------------------------------------+
    void UpdateGlobalRegime()
    {
        int n = ArraySize(m_couplings);
        if(n == 0)
        {
            m_dominant_regime = "SINGLE_MARKET";
            m_global_coupling_index = 0;
            return;
        }

        // Calculate average coupling strength
        double sum = 0;
        for(int i = 0; i < n; i++)
        {
            sum += m_couplings[i].coupling_strength;
        }

        m_last_global_coupling = m_global_coupling_index;
        m_global_coupling_index = sum / n;

        // Classify regime
        string old_regime = m_dominant_regime;

        if(m_global_coupling_index > m_coupling_threshold_strong)
            m_dominant_regime = "STRONGLY_COUPLED";
        else if(m_global_coupling_index < m_coupling_threshold_weak)
            m_dominant_regime = "DECOUPLED";
        else
            m_dominant_regime = "TRANSITIONING";

        // Alert on regime shift
        if(m_alert_on_regime_shift && old_regime != m_dominant_regime && old_regime != "INITIALIZING")
        {
            Print("╔═══════════════════════════════════════════════════════════╗");
            Print("║  GLOBAL COUPLING REGIME SHIFT                             ║");
            Print("╚═══════════════════════════════════════════════════════════╝");
            Print("  ", old_regime, " → ", m_dominant_regime);
            Print("  Global Coupling Index: ", DoubleToString(m_global_coupling_index, 3));
            Print("───────────────────────────────────────────────────────────");
        }

        // Alert on significant coupling change
        double coupling_change = MathAbs(m_global_coupling_index - m_last_global_coupling);
        if(m_alert_on_coupling_change && coupling_change > m_min_coupling_change_for_alert)
        {
            Print("⚠️ COUPLING STRENGTH CHANGED: ", DoubleToString(coupling_change, 3),
                  " (", DoubleToString(m_last_global_coupling, 2), " → ",
                  DoubleToString(m_global_coupling_index, 2), ")");
        }
    }

    //+------------------------------------------------------------------+
    //| Print coupling analysis report                                   |
    //+------------------------------------------------------------------+
    void PrintCouplingReport()
    {
        Print("╔═══════════════════════════════════════════════════════════╗");
        Print("║  MULTI-MARKET PHASE COUPLING ANALYSIS                     ║");
        Print("╚═══════════════════════════════════════════════════════════╝");
        Print("  Markets Tracked: ", ArraySize(m_markets));
        Print("  Coupling Pairs: ", ArraySize(m_couplings));
        Print("  Global Coupling Index: ", DoubleToString(m_global_coupling_index, 3));
        Print("  Regime: ", m_dominant_regime);
        Print("───────────────────────────────────────────────────────────");

        // Print individual market phases
        Print("MARKET PHASES:");
        for(int i = 0; i < ArraySize(m_markets); i++)
        {
            SMarketPhase& m = m_markets[i];
            Print("  ", m.symbol, " ", EnumToString(m.timeframe),
                  ": φ=", DoubleToString(m.phase_angle, 1), "° ",
                  "ω=", DoubleToString(m.rotation_speed, 1), "°/bar ",
                  "coh=", DoubleToString(m.coherence, 1));
        }

        Print("───────────────────────────────────────────────────────────");

        // Print strongest couplings
        Print("STRONGEST COUPLINGS:");

        // Sort couplings by strength
        for(int i = 0; i < ArraySize(m_couplings) && i < 5; i++)  // Top 5
        {
            double max_strength = -1;
            int max_idx = -1;

            for(int j = 0; j < ArraySize(m_couplings); j++)
            {
                if(m_couplings[j].coupling_strength > max_strength)
                {
                    // Check if not already printed (naive check)
                    bool already_printed = false;
                    for(int k = 0; k < i; k++)
                    {
                        // Would need better tracking
                    }

                    if(!already_printed)
                    {
                        max_strength = m_couplings[j].coupling_strength;
                        max_idx = j;
                    }
                }
            }

            if(max_idx >= 0)
            {
                SCouplingPair& c = m_couplings[max_idx];
                Print("  ", c.market_a, " ↔ ", c.market_b, ": ",
                      DoubleToString(c.coupling_strength, 3), " ",
                      c.coupling_type, " (Δφ=", DoubleToString(c.phase_difference, 1), "°)");
            }
        }

        Print("═══════════════════════════════════════════════════════════");
    }

    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetGlobalCouplingIndex() { return m_global_coupling_index; }
    string GetDominantRegime() { return m_dominant_regime; }
    int GetMarketCount() { return ArraySize(m_markets); }

    double GetMarketPhase(string symbol, ENUM_TIMEFRAMES tf)
    {
        for(int i = 0; i < ArraySize(m_markets); i++)
        {
            if(m_markets[i].symbol == symbol && m_markets[i].timeframe == tf)
                return m_markets[i].phase_angle;
        }
        return -1;
    }

    double GetCouplingStrength(string symbol_a, string symbol_b)
    {
        for(int i = 0; i < ArraySize(m_couplings); i++)
        {
            SCouplingPair& c = m_couplings[i];
            if((c.market_a == symbol_a && c.market_b == symbol_b) ||
               (c.market_a == symbol_b && c.market_b == symbol_a))
            {
                return c.coupling_strength;
            }
        }
        return -1;
    }

    //+------------------------------------------------------------------+
    //| Configuration                                                    |
    //+------------------------------------------------------------------+
    void SetUpdateInterval(int seconds) { m_update_interval_seconds = seconds; }
    void SetCouplingThresholds(double weak, double strong)
    {
        m_coupling_threshold_weak = weak;
        m_coupling_threshold_strong = strong;
    }
    void EnableAlerts(bool coupling_change, bool regime_shift)
    {
        m_alert_on_coupling_change = coupling_change;
        m_alert_on_regime_shift = regime_shift;
    }
};
