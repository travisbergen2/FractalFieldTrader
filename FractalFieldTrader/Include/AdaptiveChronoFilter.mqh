//+------------------------------------------------------------------+
//| AdaptiveChronoFilter.mqh                                         |
//| Dynamic Temporal Bandwidth Adjustment                            |
//| Adapts α parameter based on field state and market rhythm        |
//+------------------------------------------------------------------+

class CAdaptiveChronoFilter
{
private:
    // Adaptive parameters
    double m_current_alpha;           // Current EMA smoothing factor
    double m_current_tick_bar_size;   // Current market-time bar size
    int m_current_event_spacing;      // Current minimum event spacing

    double m_novelty_threshold;       // Adaptive novelty trigger
    double m_rotation_threshold;      // Adaptive rotation trigger

    // State tracking
    string m_current_regime;          // Current temporal regime
    double m_regime_confidence;       // How confident are we in this regime

    // Historical regime tracking
    string m_regime_history[];
    datetime m_regime_change_times[];
    int m_regime_history_size;

    // Adaptation rate limits
    double m_min_alpha;
    double m_max_alpha;
    double m_alpha_adjustment_rate;   // How fast α can change

public:
    CAdaptiveChronoFilter()
    {
        // Initialize with neutral values
        m_current_alpha = 0.1;
        m_current_tick_bar_size = 100;
        m_current_event_spacing = 2;

        m_novelty_threshold = 3.0;
        m_rotation_threshold = 0.15;

        m_current_regime = "NEUTRAL";
        m_regime_confidence = 0.5;

        // Set adaptation bounds
        m_min_alpha = 0.02;   // Slowest (most smoothing)
        m_max_alpha = 0.5;    // Fastest (most reactive)
        m_alpha_adjustment_rate = 0.05;  // Max change per update

        // Setup history tracking
        m_regime_history_size = 50;
        ArrayResize(m_regime_history, m_regime_history_size);
        ArrayResize(m_regime_change_times, m_regime_history_size);
        ArrayInitialize(m_regime_history, "");
        ArrayInitialize(m_regime_change_times, 0);
    }

    //+------------------------------------------------------------------+
    //| Main adaptation function - call this on each coherence update   |
    //+------------------------------------------------------------------+
    void Adapt(CCoherenceMeasure* field)
    {
        if(CheckPointer(field) == POINTER_INVALID)
            return;

        // Get field state components
        string attractor = field.GetCurrentAttractor();
        double phase_angle = field.GetPhaseAngle();
        double rotation_speed = field.GetRotationSpeed();
        double memory_density = field.GetMemoryDensity();
        double coherence = field.GetOverallCoherence();
        double alignment = field.GetFieldAlignment();

        // Get temporal metrics
        CTemporalState* temporal = field.GetTemporalEngine();
        if(CheckPointer(temporal) == POINTER_INVALID)
            return;

        double rhythm_strength = temporal.GetRhythmStrength();
        double temporal_compression = temporal.GetTemporalCompression();
        double dominant_period = temporal.GetDominantPeriod();

        // Get emotional metrics
        CEmotionalState* emotional = field.GetEmotionalEngine();
        if(CheckPointer(emotional) == POINTER_INVALID)
            return;

        double vol_percentile = emotional.GetVolatilityPercentile();
        double panic_index = emotional.GetPanicIndex();

        // Classify temporal regime
        ClassifyTemporalRegime(attractor, rhythm_strength, temporal_compression,
                              vol_percentile, memory_density, coherence);

        // Calculate optimal α for current regime
        double target_alpha = CalculateOptimalAlpha(rhythm_strength, temporal_compression,
                                                    vol_percentile, attractor);

        // Smooth the α transition (don't jump abruptly)
        double alpha_change = target_alpha - m_current_alpha;
        alpha_change = MathMax(-m_alpha_adjustment_rate, MathMin(m_alpha_adjustment_rate, alpha_change));
        m_current_alpha += alpha_change;
        m_current_alpha = MathMax(m_min_alpha, MathMin(m_max_alpha, m_current_alpha));

        // Adapt tick bar size based on frame rate and volatility
        AdaptTickBarSize(temporal, emotional);

        // Adapt event spacing based on dominant period
        AdaptEventSpacing(dominant_period, rhythm_strength, memory_density);

        // Adapt thresholds based on field state
        AdaptThresholds(coherence, alignment, vol_percentile, panic_index);
    }

    //+------------------------------------------------------------------+
    //| Classify the current temporal regime                            |
    //+------------------------------------------------------------------+
    void ClassifyTemporalRegime(string attractor, double rhythm_strength,
                               double temporal_compression, double vol_percentile,
                               double memory_density, double coherence)
    {
        string new_regime = "";
        double confidence = 0;

        // HIGH COHERENCE FLOW STATE
        // Strong rhythm + high compression + high memory = predictable flow
        if(coherence > 65 && rhythm_strength > 50 && temporal_compression > 60 && memory_density > 60)
        {
            new_regime = "FLOW_STATE";
            confidence = 0.9;
        }
        // RHYTHMIC COMPRESSION
        // Market moving fast with detectable cycles
        else if(rhythm_strength > 40 && temporal_compression > 55)
        {
            new_regime = "RHYTHMIC_COMPRESSION";
            confidence = 0.75;
        }
        // CHAOTIC ACCELERATION
        // High compression but no rhythm = dangerous speed
        else if(temporal_compression > 70 && rhythm_strength < 30)
        {
            new_regime = "CHAOTIC_ACCELERATION";
            confidence = 0.8;
        }
        // TEMPORAL DRAG
        // Low activity, time dragging
        else if(temporal_compression < 40 && vol_percentile < 40)
        {
            new_regime = "TEMPORAL_DRAG";
            confidence = 0.7;
        }
        // VOLATILITY STORM
        // High volatility without structure
        else if(vol_percentile > 75 && rhythm_strength < 30 && coherence < 50)
        {
            new_regime = "VOLATILITY_STORM";
            confidence = 0.85;
        }
        // PATTERN EMERGENCE
        // Rhythm building, memory forming
        else if(rhythm_strength > 30 && memory_density > 50 && coherence > 55)
        {
            new_regime = "PATTERN_EMERGENCE";
            confidence = 0.65;
        }
        // NEUTRAL/UNCERTAIN
        else
        {
            new_regime = "NEUTRAL";
            confidence = 0.5;
        }

        // Check for regime change
        if(new_regime != m_current_regime)
        {
            LogRegimeChange(m_current_regime, new_regime);
            m_current_regime = new_regime;
        }

        m_regime_confidence = confidence;
    }

    //+------------------------------------------------------------------+
    //| Calculate optimal α for current conditions                      |
    //+------------------------------------------------------------------+
    double CalculateOptimalAlpha(double rhythm_strength, double temporal_compression,
                                double vol_percentile, string attractor)
    {
        double alpha = 0.1;  // Default baseline

        // RHYTHM ADJUSTMENT
        // Strong rhythm = lower α (trust the smoothing, don't chase noise)
        if(rhythm_strength > 60)
            alpha *= 0.5;   // Very smooth
        else if(rhythm_strength > 40)
            alpha *= 0.75;  // Moderately smooth
        else if(rhythm_strength < 20)
            alpha *= 1.5;   // More reactive when no rhythm

        // TEMPORAL COMPRESSION ADJUSTMENT
        // High compression = need faster response
        if(temporal_compression > 70)
            alpha *= 1.4;
        else if(temporal_compression < 40)
            alpha *= 0.7;  // Slow market = smooth more

        // VOLATILITY ADJUSTMENT
        // Extreme volatility = don't overreact
        if(vol_percentile > 80)
            alpha *= 0.6;   // Smooth out panic
        else if(vol_percentile < 30)
            alpha *= 1.2;   // Can be more responsive in calm

        // ATTRACTOR-SPECIFIC ADJUSTMENTS
        if(attractor == "LOW_VOL_CYCLE")
            alpha *= 0.6;   // Trust the cycle, smooth heavily
        else if(attractor == "HIGH_VOL_CHAOS")
            alpha *= 1.3;   // Need to react to chaos
        else if(attractor == "TREND_MOMENTUM")
            alpha *= 0.8;   // Moderate smoothing for trends

        return alpha;
    }

    //+------------------------------------------------------------------+
    //| Adapt tick bar size for market-time bars                        |
    //+------------------------------------------------------------------+
    void AdaptTickBarSize(CTemporalState* temporal, CEmotionalState* emotional)
    {
        double frame_rate = temporal.GetFrameRate();
        double vol_percentile = emotional.GetVolatilityPercentile();

        // Base bar size
        double base_size = 100;

        // Scale with frame rate
        // High frame rate (busy market) = larger bars to maintain temporal consistency
        if(frame_rate > 50)
            base_size *= 1.5;
        else if(frame_rate > 30)
            base_size *= 1.2;
        else if(frame_rate < 10)
            base_size *= 0.7;

        // Scale with volatility
        // High volatility = more ticks needed to capture meaningful moves
        if(vol_percentile > 75)
            base_size *= 1.3;
        else if(vol_percentile < 30)
            base_size *= 0.8;

        m_current_tick_bar_size = base_size;
    }

    //+------------------------------------------------------------------+
    //| Adapt event spacing based on market rhythm                      |
    //+------------------------------------------------------------------+
    void AdaptEventSpacing(double dominant_period, double rhythm_strength,
                          double memory_density)
    {
        // Base spacing = 2 bars
        int spacing = 2;

        // If strong rhythm detected, space events according to the period
        if(rhythm_strength > 50 && dominant_period > 2)
        {
            // Space events at half the dominant period
            spacing = (int)(dominant_period / 2.0);
            spacing = MathMax(2, MathMin(10, spacing));  // Clamp to reasonable range
        }
        // High memory density = space events further (let patterns complete)
        else if(memory_density > 70)
        {
            spacing = 5;
        }
        // Chaotic low-memory market = tighter spacing (catch what you can)
        else if(memory_density < 30 && rhythm_strength < 30)
        {
            spacing = 1;
        }

        m_current_event_spacing = spacing;
    }

    //+------------------------------------------------------------------+
    //| Adapt novelty and rotation thresholds                           |
    //+------------------------------------------------------------------+
    void AdaptThresholds(double coherence, double alignment,
                        double vol_percentile, double panic_index)
    {
        // Base thresholds
        double novelty_base = 3.0;
        double rotation_base = 0.15;

        // LOW COHERENCE = RAISE BAR (be more selective)
        if(coherence < 50)
        {
            novelty_base *= 1.4;
            rotation_base *= 1.3;
        }

        // LOW ALIGNMENT = RAISE BAR (dimensions not agreeing)
        if(alignment < 45)
        {
            novelty_base *= 1.3;
            rotation_base *= 1.2;
        }

        // HIGH VOLATILITY = RAISE BAR (don't chase chaos)
        if(vol_percentile > 75)
        {
            novelty_base *= 1.5;
            rotation_base *= 1.4;
        }

        // PANIC = SIGNIFICANTLY RAISE BAR
        if(panic_index > 60)
        {
            novelty_base *= 2.0;
            rotation_base *= 1.8;
        }

        // HIGH COHERENCE + ALIGNMENT = LOWER BAR (trust the field)
        if(coherence > 70 && alignment > 65)
        {
            novelty_base *= 0.8;
            rotation_base *= 0.85;
        }

        m_novelty_threshold = novelty_base;
        m_rotation_threshold = rotation_base;
    }

    //+------------------------------------------------------------------+
    //| Log regime transitions                                           |
    //+------------------------------------------------------------------+
    void LogRegimeChange(string old_regime, string new_regime)
    {
        // Shift history
        for(int i = m_regime_history_size - 1; i > 0; i--)
        {
            m_regime_history[i] = m_regime_history[i-1];
            m_regime_change_times[i] = m_regime_change_times[i-1];
        }

        // Store new transition
        m_regime_history[0] = old_regime + "_TO_" + new_regime;
        m_regime_change_times[0] = TimeCurrent();

        // Log to journal
        Print("╔═══════════════════════════════════════════════════════════╗");
        Print("║  TEMPORAL REGIME SHIFT DETECTED                           ║");
        Print("╚═══════════════════════════════════════════════════════════╝");
        Print("  FROM: ", old_regime);
        Print("  TO:   ", new_regime);
        Print("  TIME: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
        Print("  NEW ALPHA: ", DoubleToString(m_current_alpha, 4));
        Print("───────────────────────────────────────────────────────────");
    }

    //+------------------------------------------------------------------+
    //| Getters for adapted parameters                                   |
    //+------------------------------------------------------------------+
    double GetCurrentAlpha() { return m_current_alpha; }
    double GetCurrentTickBarSize() { return m_current_tick_bar_size; }
    int GetCurrentEventSpacing() { return m_current_event_spacing; }
    double GetNoveltyThreshold() { return m_novelty_threshold; }
    double GetRotationThreshold() { return m_rotation_threshold; }
    string GetCurrentRegime() { return m_current_regime; }
    double GetRegimeConfidence() { return m_regime_confidence; }

    //+------------------------------------------------------------------+
    //| Get regime statistics                                            |
    //+------------------------------------------------------------------+
    void PrintRegimeAnalysis()
    {
        Print("═══════════ ADAPTIVE CHRONOCEPTIVE ANALYSIS ═══════════");
        Print("Current Regime: ", m_current_regime, " (", DoubleToString(m_regime_confidence * 100, 1), "% confidence)");
        Print("");
        Print("Adapted Parameters:");
        Print("  Alpha (α):           ", DoubleToString(m_current_alpha, 4));
        Print("  Tick Bar Size:       ", DoubleToString(m_current_tick_bar_size, 0), " ticks");
        Print("  Event Spacing:       ", m_current_event_spacing, " bars");
        Print("  Novelty Threshold:   ", DoubleToString(m_novelty_threshold, 2));
        Print("  Rotation Threshold:  ", DoubleToString(m_rotation_threshold, 3));
        Print("");
        Print("Recent Regime History:");
        for(int i = 0; i < 5 && i < m_regime_history_size; i++)
        {
            if(m_regime_history[i] != "")
                Print("  [", i, "] ", m_regime_history[i], " @ ", TimeToString(m_regime_change_times[i], TIME_MINUTES));
        }
        Print("═══════════════════════════════════════════════════════");
    }

    //+------------------------------------------------------------------+
    //| Check if current regime favors trading                          |
    //+------------------------------------------------------------------+
    bool IsRegimeFavorable()
    {
        // Favorable regimes
        if(m_current_regime == "FLOW_STATE") return true;
        if(m_current_regime == "RHYTHMIC_COMPRESSION") return true;
        if(m_current_regime == "PATTERN_EMERGENCE") return true;

        // Unfavorable regimes
        if(m_current_regime == "CHAOTIC_ACCELERATION") return false;
        if(m_current_regime == "VOLATILITY_STORM") return false;

        // Neutral/uncertain = allow but with caution
        return true;
    }

    //+------------------------------------------------------------------+
    //| Get position size multiplier based on regime                    |
    //+------------------------------------------------------------------+
    double GetRegimeMultiplier()
    {
        if(m_current_regime == "FLOW_STATE")
            return 1.5;  // High confidence

        if(m_current_regime == "RHYTHMIC_COMPRESSION")
            return 1.2;

        if(m_current_regime == "PATTERN_EMERGENCE")
            return 1.1;

        if(m_current_regime == "CHAOTIC_ACCELERATION")
            return 0.5;  // Reduce size

        if(m_current_regime == "VOLATILITY_STORM")
            return 0.4;  // Heavily reduce

        if(m_current_regime == "TEMPORAL_DRAG")
            return 0.7;  // Moderate reduction

        return 1.0;  // Neutral
    }
};
