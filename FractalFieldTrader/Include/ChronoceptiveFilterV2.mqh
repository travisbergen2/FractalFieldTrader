//+------------------------------------------------------------------+
//| ChronoceptiveFilterV2.mqh - ADAPTIVE TEMPORAL BANDWIDTH          |
//| NOW WITH ADAPTIVE ALPHA AND DYNAMIC THRESHOLDS                   |
//+------------------------------------------------------------------+

#include "AdaptiveChronoFilter.mqh"

class CChronoceptiveFilterV2
{
private:
    double m_last_coherence;
    double m_last_alignment;
    double m_last_buy_pressure;
    double m_last_sell_pressure;

    double m_novelty_threshold;
    double m_rotation_threshold;

    datetime m_last_event;
    int m_min_event_spacing_bars;

    double m_S_strength;
    double m_A_strength;

    double m_novelty_ema;
    double m_rotation_ema;

    // ADAPTIVE FILTER - THE GAME CHANGER
    CAdaptiveChronoFilter* m_adaptive_filter;

    // Current alpha (retrieved from adaptive filter)
    double m_current_alpha;

public:
    CChronoceptiveFilterV2()
    {
        m_last_coherence = 0;
        m_last_alignment = 0;
        m_last_buy_pressure = 50;
        m_last_sell_pressure = 50;

        m_novelty_threshold = 5.0;
        m_rotation_threshold = 0.25;

        m_last_event = 0;
        m_min_event_spacing_bars = 2;

        m_S_strength = 0;
        m_A_strength = 0;

        m_novelty_ema = 5.0;
        m_rotation_ema = 0.3;

        m_current_alpha = 0.1;  // Starting value

        // Initialize adaptive filter
        m_adaptive_filter = new CAdaptiveChronoFilter();
    }

    ~CChronoceptiveFilterV2()
    {
        if(CheckPointer(m_adaptive_filter) == POINTER_DYNAMIC)
            delete m_adaptive_filter;
    }

    //+------------------------------------------------------------------+
    //| Main market speaking detection - NOW ADAPTIVE                   |
    //+------------------------------------------------------------------+
    bool IsMarketSpeaking(CCoherenceMeasure* field)
    {
        if(CheckPointer(field) == POINTER_INVALID)
            return false;

        // STEP 1: UPDATE ADAPTIVE PARAMETERS
        if(CheckPointer(m_adaptive_filter) != POINTER_INVALID)
        {
            m_adaptive_filter.Adapt(field);

            // Get adapted parameters
            m_current_alpha = m_adaptive_filter.GetCurrentAlpha();
            m_novelty_threshold = m_adaptive_filter.GetNoveltyThreshold();
            m_rotation_threshold = m_adaptive_filter.GetRotationThreshold();
            m_min_event_spacing_bars = m_adaptive_filter.GetCurrentEventSpacing();
        }

        // STEP 2: CALCULATE CURRENT STATE
        double coherence = field.GetOverallCoherence();
        double alignment = field.GetFieldAlignment();

        CIntentionalState* intent = field.GetIntentionalEngine();
        if(CheckPointer(intent) == POINTER_INVALID)
            return false;

        double buy = intent.GetBuyPressure();
        double sell = intent.GetSellPressure();

        double coh_change = MathAbs(coherence - m_last_coherence);
        double align_change = MathAbs(alignment - m_last_alignment);
        double pressure_change = MathAbs((buy - sell) - (m_last_buy_pressure - m_last_sell_pressure));

        double novelty = coh_change + align_change + (pressure_change / 10.0);

        // STEP 3: ADAPTIVE EMA SMOOTHING (using dynamic alpha)
        if(m_novelty_ema == 5.0 && novelty > 0)
            m_novelty_ema = novelty;
        else
            m_novelty_ema = (1.0 - m_current_alpha) * m_novelty_ema + m_current_alpha * novelty;

        // STEP 4: COMPUTE S/A MATRICES
        ComputeSAMatrices(field, coherence, alignment, buy, sell);

        // Adaptive EMA for rotation
        if(m_rotation_ema == 0.3 && m_A_strength > 0)
            m_rotation_ema = m_A_strength;
        else
            m_rotation_ema = (1.0 - m_current_alpha) * m_rotation_ema + m_current_alpha * m_A_strength;

        // STEP 5: ADAPTIVE TRIGGER DETECTION
        bool novelty_spike = (novelty > m_novelty_threshold);
        bool rotation_active = (m_A_strength > m_rotation_threshold);

        // STEP 6: EVENT SPACING CHECK (now adaptive)
        bool spacing_ok = true;
        if(m_last_event > 0)
        {
            int seconds_since = (int)(TimeCurrent() - m_last_event);
            int bar_period = PeriodSeconds(PERIOD_CURRENT);
            int bars_since_last = seconds_since / bar_period;
            spacing_ok = (bars_since_last >= m_min_event_spacing_bars);
        }

        // STEP 7: CHECK REGIME FAVORABILITY (new!)
        bool regime_favorable = true;
        if(CheckPointer(m_adaptive_filter) != POINTER_INVALID)
            regime_favorable = m_adaptive_filter.IsRegimeFavorable();

        bool is_speaking = novelty_spike && rotation_active && spacing_ok && regime_favorable;

        // STEP 8: LOG IF DETECTED
        if(is_speaking)
        {
            m_last_event = TimeCurrent();
            Print("╔═══════════════════════════════════════════════════════════╗");
            Print("║  CHRONOCEPTIVE EVENT DETECTED (ADAPTIVE)                  ║");
            Print("╚═══════════════════════════════════════════════════════════╝");
            Print("  Novelty:     ", DoubleToString(novelty, 2), " (threshold: ", DoubleToString(m_novelty_threshold, 2), ")");
            Print("  S-matrix:    ", DoubleToString(m_S_strength, 3));
            Print("  A-matrix:    ", DoubleToString(m_A_strength, 3), " (threshold: ", DoubleToString(m_rotation_threshold, 3), ")");
            Print("  Alpha (α):   ", DoubleToString(m_current_alpha, 4));

            if(CheckPointer(m_adaptive_filter) != POINTER_INVALID)
            {
                Print("  Regime:      ", m_adaptive_filter.GetCurrentRegime());
                Print("  Confidence:  ", DoubleToString(m_adaptive_filter.GetRegimeConfidence() * 100, 1), "%");
            }
            Print("───────────────────────────────────────────────────────────");
        }

        // STEP 9: UPDATE HISTORY
        m_last_coherence = coherence;
        m_last_alignment = alignment;
        m_last_buy_pressure = buy;
        m_last_sell_pressure = sell;

        return is_speaking;
    }

    //+------------------------------------------------------------------+
    //| FIXED S/A MATRIX CALCULATION - Direct scaling 0-1               |
    //+------------------------------------------------------------------+
    void ComputeSAMatrices(CCoherenceMeasure* field, double coh, double align, double buy, double sell)
    {
        // FIXED FORMULA: Direct scaling 0-1
        double consensus_base = (coh / 100.0) * (align / 100.0);

        double pressure_agreement = 0;
        if(buy > sell)
            pressure_agreement = buy / 100.0;
        else
            pressure_agreement = sell / 100.0;

        m_S_strength = consensus_base * pressure_agreement;

        // A-matrix (rotation/volatility)
        double pressure_magnitude = (buy + sell) / 200.0;
        double pressure_balance = 1.0 - MathAbs(buy - sell) / 100.0;

        m_A_strength = pressure_magnitude * pressure_balance;

        // Boost A with emotional conflict
        CEmotionalState* emo = field.GetEmotionalEngine();
        if(CheckPointer(emo) != POINTER_INVALID)
        {
            double greed = emo.GetGreedLevel();
            double fear = emo.GetFearLevel();
            double emotional_conflict = MathAbs(greed - fear) / 100.0;

            // Reduced from 1.0 to 0.5 multiplier
            m_A_strength = m_A_strength * (1.0 + emotional_conflict * 0.5);
        }

        m_S_strength = MathMax(0, MathMin(1.0, m_S_strength));
        m_A_strength = MathMax(0, MathMin(1.0, m_A_strength));
    }

    //+------------------------------------------------------------------+
    //| Get decision potential                                           |
    //+------------------------------------------------------------------+
    double GetDecisionPotential()
    {
        return m_S_strength - (0.5 * m_A_strength);
    }

    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetSStrength() { return m_S_strength; }
    double GetAStrength() { return m_A_strength; }
    double GetCurrentAlpha() { return m_current_alpha; }

    //+------------------------------------------------------------------+
    //| Get consensus direction                                          |
    //+------------------------------------------------------------------+
    int GetConsensusDirection(CCoherenceMeasure* field)
    {
        CIntentionalState* intent = field.GetIntentionalEngine();
        if(CheckPointer(intent) == POINTER_INVALID)
            return 0;

        double buy = intent.GetBuyPressure();
        double sell = intent.GetSellPressure();

        if(buy > sell + 5.0)
            return 1;
        else if(sell > buy + 5.0)
            return -1;

        return 0;
    }

    //+------------------------------------------------------------------+
    //| Print full adaptive analysis                                     |
    //+------------------------------------------------------------------+
    void PrintAdaptiveAnalysis()
    {
        if(CheckPointer(m_adaptive_filter) != POINTER_INVALID)
            m_adaptive_filter.PrintRegimeAnalysis();
    }

    //+------------------------------------------------------------------+
    //| Get regime-based position size multiplier                        |
    //+------------------------------------------------------------------+
    double GetRegimeMultiplier()
    {
        if(CheckPointer(m_adaptive_filter) != POINTER_INVALID)
            return m_adaptive_filter.GetRegimeMultiplier();
        return 1.0;
    }
};
