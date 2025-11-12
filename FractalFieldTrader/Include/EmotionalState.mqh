//+------------------------------------------------------------------+
//| EmotionalState.mqh                                               |
//| Market Fear/Greed & Emotional Coherence Detection                |
//| Measures market's emotional field state                          |
//+------------------------------------------------------------------+

class CEmotionalState
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_period;
    
    // Indicator handles
    int m_atr_handle;
    int m_bb_handle;
    
    // Emotional measurements
    double m_fear_level;          // 0-100: High = extreme fear
    double m_greed_level;         // 0-100: High = extreme greed
    double m_panic_index;         // 0-100: Volatility spike detection
    double m_euphoria_index;      // 0-100: Unsustainable optimism
    
    // Volatility regime
    double m_volatility_percentile;  // Where current vol sits historically
    double m_vol_of_vol;             // Stability of volatility itself
    
    // Historical tracking
    double m_fear_history[];
    double m_volatility_history[];
    
    // Regime detection
    string m_current_regime;      // CALM, ANXIOUS, PANIC, EUPHORIC
    
public:
    CEmotionalState(int period = 50)
    {
        m_period = period;
        m_atr_handle = INVALID_HANDLE;
        m_bb_handle = INVALID_HANDLE;
        
        ArrayResize(m_fear_history, 100);
        ArrayResize(m_volatility_history, 100);
        ArrayInitialize(m_fear_history, 0);
        ArrayInitialize(m_volatility_history, 0);
        
        m_fear_level = 50;
        m_greed_level = 50;
        m_panic_index = 0;
        m_euphoria_index = 0;
        m_volatility_percentile = 50;
        m_vol_of_vol = 0;
        m_current_regime = "CALM";
    }
    
    ~CEmotionalState()
    {
        if(m_atr_handle != INVALID_HANDLE)
            IndicatorRelease(m_atr_handle);
        if(m_bb_handle != INVALID_HANDLE)
            IndicatorRelease(m_bb_handle);
    }
    
    //+------------------------------------------------------------------+
    //| Initialize                                                        |
    //+------------------------------------------------------------------+
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        m_atr_handle = iATR(symbol, timeframe, 14);
        m_bb_handle = iBands(symbol, timeframe, 20, 0, 2.0, PRICE_CLOSE);
        
        if(m_atr_handle == INVALID_HANDLE || m_bb_handle == INVALID_HANDLE)
        {
            Print("EmotionalState: Failed to create indicators for ", symbol);
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate emotional coherence                                    |
    //+------------------------------------------------------------------+
    double Calculate()
    {
        if(m_atr_handle == INVALID_HANDLE)
            return 50.0;
        
        // Get current volatility
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(m_atr_handle, 0, 0, m_period, atr) < m_period)
            return 50.0;
        
        // Calculate volatility metrics
        CalculateVolatilityMetrics(atr);
        
        // Detect fear/greed
        DetectFearGreed(atr);
        
        // Detect panic/euphoria
        DetectExtremeStates();
        
        // Classify regime
        ClassifyEmotionalRegime();
        
        // Calculate coherence score
        // High coherence = stable emotional state
        // Low coherence = chaotic emotional state
        
        double coherence = 100.0 - m_vol_of_vol * 100.0;  // Low vol-of-vol = high coherence
        
        // Adjust for extreme states (panic/euphoria reduce coherence)
        if(m_panic_index > 70 || m_euphoria_index > 70)
            coherence *= 0.7;  // Extremes = less coherent
        
        return MathMax(0, MathMin(100, coherence));
    }
    
    //+------------------------------------------------------------------+
    //| Calculate volatility metrics                                     |
    //+------------------------------------------------------------------+
    void CalculateVolatilityMetrics(double &atr[])
    {
        // Calculate mean volatility
        double mean_vol = 0;
        for(int i = 0; i < m_period; i++)
            mean_vol += atr[i];
        mean_vol /= m_period;
        
        // Calculate volatility of volatility
        double variance = 0;
        for(int i = 0; i < m_period; i++)
            variance += MathPow(atr[i] - mean_vol, 2);
        variance /= m_period;
        
        double std_dev = MathSqrt(variance);
        m_vol_of_vol = (mean_vol > 0) ? (std_dev / mean_vol) : 0;
        
        // Calculate percentile (where current vol sits in historical range)
        double current_vol = atr[0];
        
        // Get historical volatility range
        double min_vol = atr[0];
        double max_vol = atr[0];
        for(int i = 0; i < m_period; i++)
        {
            if(atr[i] < min_vol) min_vol = atr[i];
            if(atr[i] > max_vol) max_vol = atr[i];
        }
        
        double range = max_vol - min_vol;
        if(range > 0)
            m_volatility_percentile = ((current_vol - min_vol) / range) * 100;
        else
            m_volatility_percentile = 50;
        
        // Store in history
        StoreVolatility(current_vol);
    }
    
    //+------------------------------------------------------------------+
    //| Detect fear and greed levels                                     |
    //+------------------------------------------------------------------+
    void DetectFearGreed(double &atr[])
    {
        // Fear = high volatility + expanding range
        // Greed = low volatility + tight range + uptrend
        
        double current_vol = atr[0];
        double avg_vol = 0;
        for(int i = 1; i < 20; i++)
            avg_vol += atr[i];
        avg_vol /= 19;
        
        // Fear increases with volatility spikes
        if(current_vol > avg_vol)
        {
            double vol_increase = (current_vol - avg_vol) / avg_vol;
            m_fear_level = 50 + (vol_increase * 100);
            m_fear_level = MathMin(100, m_fear_level);
            m_greed_level = 100 - m_fear_level;
        }
        else
        {
            // Greed in low volatility
            double vol_decrease = (avg_vol - current_vol) / avg_vol;
            m_greed_level = 50 + (vol_decrease * 100);
            m_greed_level = MathMin(100, m_greed_level);
            m_fear_level = 100 - m_greed_level;
        }
        
        // Check price action for confirmation
        double closes[];
        ArraySetAsSeries(closes, true);
        if(CopyClose(m_symbol, m_timeframe, 0, 10, closes) == 10)
        {
            bool uptrend = true;
            for(int i = 0; i < 9; i++)
            {
                if(closes[i] < closes[i+1])
                {
                    uptrend = false;
                    break;
                }
            }
            
            // Sustained uptrend + low vol = greed
            if(uptrend && m_greed_level > 60)
                m_greed_level = MathMin(100, m_greed_level * 1.2);
        }
        
        StoreFear(m_fear_level);
    }
    
    //+------------------------------------------------------------------+
    //| Detect extreme emotional states (panic/euphoria)                 |
    //+------------------------------------------------------------------+
    void DetectExtremeStates()
    {
        // Panic = rapid volatility spike + high percentile
        if(m_volatility_percentile > 80)
        {
            double vol_gradient = GetVolatilityGradient();
            if(vol_gradient > 0.3)  // 30% increase in volatility
            {
                m_panic_index = 50 + (vol_gradient * 100);
                m_panic_index = MathMin(100, m_panic_index);
            }
            else
            {
                m_panic_index *= 0.9;  // Decay if not increasing
            }
        }
        else
        {
            m_panic_index *= 0.8;  // Decay
        }
        
        // Euphoria = sustained low volatility at high prices
        if(m_volatility_percentile < 30 && m_greed_level > 70)
        {
            m_euphoria_index = m_greed_level;
        }
        else
        {
            m_euphoria_index *= 0.8;  // Decay
        }
    }
    
    //+------------------------------------------------------------------+
    //| Classify emotional regime                                        |
    //+------------------------------------------------------------------+
    void ClassifyEmotionalRegime()
    {
        // PANIC: High fear + high vol + panic index
        if(m_panic_index > 60)
        {
            m_current_regime = "PANIC";
        }
        // EUPHORIA: High greed + low vol + euphoria index
        else if(m_euphoria_index > 60)
        {
            m_current_regime = "EUPHORIC";
        }
        // ANXIOUS: Elevated fear but not panic
        else if(m_fear_level > 65)
        {
            m_current_regime = "ANXIOUS";
        }
        // CALM: Neutral state
        else
        {
            m_current_regime = "CALM";
        }
    }
    
    //+------------------------------------------------------------------+
    //| Get volatility gradient (rate of change)                         |
    //+------------------------------------------------------------------+
    double GetVolatilityGradient()
    {
        if(ArraySize(m_volatility_history) < 5)
            return 0;
        
        double recent = m_volatility_history[0];
        double past = m_volatility_history[4];
        
        if(past == 0) return 0;
        
        return (recent - past) / past;
    }
    
    //+------------------------------------------------------------------+
    //| Detect emotional transitions                                     |
    //+------------------------------------------------------------------+
    string DetectEmotionalTransition()
    {
        // Check for regime changes
        static string prev_regime = "CALM";
        
        if(m_current_regime != prev_regime)
        {
            string transition = prev_regime + "_TO_" + m_current_regime;
            prev_regime = m_current_regime;
            return transition;
        }
        
        // Check for panic onset
        if(m_panic_index > 70 && GetPanicGradient() > 20)
            return "PANIC_ONSET";
        
        // Check for fear subsiding (recovery)
        if(m_fear_level < 40 && GetFearGradient() < -10)
            return "FEAR_SUBSIDING";
        
        return "STABLE";
    }
    
    //+------------------------------------------------------------------+
    //| Get panic gradient                                               |
    //+------------------------------------------------------------------+
    double GetPanicGradient()
    {
        // Simplified - would need panic history tracking
        return m_panic_index;
    }
    
    //+------------------------------------------------------------------+
    //| Get fear gradient                                                |
    //+------------------------------------------------------------------+
    double GetFearGradient()
    {
        if(ArraySize(m_fear_history) < 5)
            return 0;
        
        return m_fear_history[0] - m_fear_history[4];
    }
    
    //+------------------------------------------------------------------+
    //| Store in history                                                 |
    //+------------------------------------------------------------------+
    void StoreFear(double fear)
    {
        for(int i = ArraySize(m_fear_history) - 1; i > 0; i--)
            m_fear_history[i] = m_fear_history[i-1];
        m_fear_history[0] = fear;
    }
    
    void StoreVolatility(double vol)
    {
        for(int i = ArraySize(m_volatility_history) - 1; i > 0; i--)
            m_volatility_history[i] = m_volatility_history[i-1];
        m_volatility_history[0] = vol;
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetFearLevel() { return m_fear_level; }
    double GetGreedLevel() { return m_greed_level; }
    double GetPanicIndex() { return m_panic_index; }
    double GetEuphoriaIndex() { return m_euphoria_index; }
    double GetVolatilityPercentile() { return m_volatility_percentile; }
    string GetCurrentRegime() { return m_current_regime; }
    
    //+------------------------------------------------------------------+
    //| Check if safe to trade                                          |
    //+------------------------------------------------------------------+
    bool IsSafeToTrade()
    {
        // Don't trade during panic or extreme euphoria
        return (m_panic_index < 70 && m_euphoria_index < 80);
    }
    
    //+------------------------------------------------------------------+
    //| Get recommended position size adjustment                         |
    //+------------------------------------------------------------------+
    double GetPositionSizeMultiplier()
    {
        // Reduce size in high fear/panic
        if(m_panic_index > 60)
            return 0.5;  // Half size
        
        if(m_fear_level > 70)
            return 0.7;  // Reduced size
        
        // Reduce size in extreme euphoria (reversals coming)
        if(m_euphoria_index > 70)
            return 0.6;
        
        // Normal size in calm/moderate states
        return 1.0;
    }
};