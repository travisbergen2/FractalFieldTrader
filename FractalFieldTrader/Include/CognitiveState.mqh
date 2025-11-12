//+------------------------------------------------------------------+
//| CognitiveState.mqh                                               |
//| Pattern Clarity & Cognitive Complexity Detection                 |
//| Measures market's cognitive field state                          |
//+------------------------------------------------------------------+

class CCognitiveState
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_period;
    
    // Cognitive measurements
    double m_pattern_clarity;
    double m_fractal_dimension;
    double m_information_entropy;
    double m_signal_to_noise;
    
    // Pattern detection
    bool m_trend_detected;
    bool m_range_detected;
    bool m_pattern_conflict;
    
    // Historical tracking
    double m_clarity_history[];
    double m_entropy_history[];
    
    // Cognitive regime
    string m_cognitive_state;
    
public:
    CCognitiveState(int period = 50)
    {
        m_period = period;
        
        ArrayResize(m_clarity_history, 100);
        ArrayResize(m_entropy_history, 100);
        ArrayInitialize(m_clarity_history, 0);
        ArrayInitialize(m_entropy_history, 0);
        
        m_pattern_clarity = 50;
        m_fractal_dimension = 1.5;
        m_information_entropy = 50;
        m_signal_to_noise = 50;
        
        m_trend_detected = false;
        m_range_detected = false;
        m_pattern_conflict = false;
        
        m_cognitive_state = "DISCOVERING";
    }
    
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        return true;
    }
    
    double Calculate()
    {
        double closes[];
        double highs[];
        double lows[];
        
        ArraySetAsSeries(closes, true);
        ArraySetAsSeries(highs, true);
        ArraySetAsSeries(lows, true);
        
        if(CopyClose(m_symbol, m_timeframe, 0, m_period, closes) < m_period ||
           CopyHigh(m_symbol, m_timeframe, 0, m_period, highs) < m_period ||
           CopyLow(m_symbol, m_timeframe, 0, m_period, lows) < m_period)
        {
            return 50.0;
        }
        
        CalculateFractalDimension(closes);
        CalculatePatternClarity(closes, highs, lows);
        CalculateInformationEntropy(closes);
        DetectPatterns(closes);
        ClassifyCognitiveState();
        
        double coherence = 0;
        coherence += m_pattern_clarity * 0.4;
        
        double fractal_score = (2.0 - m_fractal_dimension) * 100;
        coherence += fractal_score * 0.3;
        coherence += m_signal_to_noise * 0.3;
        
        if(m_pattern_conflict)
            coherence *= 0.7;
        
        return MathMax(0, MathMin(100, coherence));
    }
    
    void CalculateFractalDimension(double &prices[])
    {
        double returns[];
        int n = ArraySize(prices);
        ArrayResize(returns, n-1);
        
        for(int i = 0; i < n-1; i++)
        {
            if(prices[i+1] != 0)
                returns[i] = (prices[i] - prices[i+1]) / prices[i+1];
            else
                returns[i] = 0;
        }
        
        double mean = 0;
        for(int i = 0; i < ArraySize(returns); i++)
            mean += returns[i];
        mean /= ArraySize(returns);
        
        double variance = 0;
        for(int i = 0; i < ArraySize(returns); i++)
            variance += MathPow(returns[i] - mean, 2);
        variance /= ArraySize(returns);
        double std_dev = MathSqrt(variance);
        
        double mean_abs = 0;
        for(int i = 0; i < ArraySize(returns); i++)
            mean_abs += MathAbs(returns[i]);
        mean_abs /= ArraySize(returns);
        
        double hurst = 0.5;
        if(std_dev > 0 && mean_abs > 0)
        {
            double ratio = mean_abs / std_dev;
            hurst = MathLog(ratio) / MathLog(ArraySize(returns));
            hurst = MathMax(0, MathMin(1, hurst));
        }
        
        m_fractal_dimension = 2.0 - hurst;
    }
    
    void CalculatePatternClarity(double &closes[], double &highs[], double &lows[])
    {
        int trend_bars = 0;
        int counter_bars = 0;
        
        for(int i = 1; i < MathMin(20, ArraySize(closes)-1); i++)
        {
            if(closes[i-1] > closes[i] && highs[i-1] > highs[i])
                trend_bars++;
            else if(closes[i-1] < closes[i] && lows[i-1] < lows[i])
                trend_bars++;
            else
                counter_bars++;
        }
        
        double trend_consistency = (double)trend_bars / (trend_bars + counter_bars);
        double range_respect = CheckRangeRespect(closes, highs, lows);
        
        m_pattern_clarity = MathMax(trend_consistency, range_respect) * 100;
        StoreClarity(m_pattern_clarity);
    }
    
    double CheckRangeRespect(double &closes[], double &highs[], double &lows[])
    {
        int lookback = MathMin(20, ArraySize(closes));
        double range_high = highs[0];
        double range_low = lows[0];
        
        for(int i = 0; i < lookback; i++)
        {
            if(highs[i] > range_high) range_high = highs[i];
            if(lows[i] < range_low) range_low = lows[i];
        }
        
        double range = range_high - range_low;
        if(range == 0) return 0;
        
        int respects = 0;
        int tests = 0;
        
        for(int i = 0; i < lookback; i++)
        {
            double position = (closes[i] - range_low) / range;
            
            if(position > 0.9 || position < 0.1)
            {
                tests++;
                
                if(i < lookback - 1)
                {
                    double next_position = (closes[i+1] - range_low) / range;
                    if((position > 0.9 && next_position < position) ||
                       (position < 0.1 && next_position > position))
                    {
                        respects++;
                    }
                }
            }
        }
        
        return (tests > 0) ? ((double)respects / tests) : 0;
    }
    
    void CalculateInformationEntropy(double &prices[])
    {
        double changes[];
        int n = ArraySize(prices);
        ArrayResize(changes, n-1);
        
        for(int i = 0; i < n-1; i++)
            changes[i] = prices[i] - prices[i+1];
        
        int num_bins = 10;
        int bins[];
        ArrayResize(bins, num_bins);
        ArrayInitialize(bins, 0);
        
        double min_change = changes[0];
        double max_change = changes[0];
        for(int i = 0; i < ArraySize(changes); i++)
        {
            if(changes[i] < min_change) min_change = changes[i];
            if(changes[i] > max_change) max_change = changes[i];
        }
        
        double range = max_change - min_change;
        if(range == 0)
        {
            m_information_entropy = 0;
            m_signal_to_noise = 100;
            return;
        }
        
        for(int i = 0; i < ArraySize(changes); i++)
        {
            int bin = (int)((changes[i] - min_change) / range * (num_bins - 1));
            bin = MathMax(0, MathMin(num_bins-1, bin));
            bins[bin]++;
        }
        
        double entropy = 0;
        for(int i = 0; i < num_bins; i++)
        {
            if(bins[i] > 0)
            {
                double p = (double)bins[i] / ArraySize(changes);
                entropy -= p * MathLog(p) / MathLog(2);
            }
        }
        
        double max_entropy = MathLog(num_bins) / MathLog(2);
        m_information_entropy = (entropy / max_entropy) * 100;
        m_signal_to_noise = 100 - m_information_entropy;
        
        StoreEntropy(m_information_entropy);
    }
    
    void DetectPatterns(double &closes[])
    {
        int up_count = 0;
        int down_count = 0;
        
        for(int i = 0; i < MathMin(10, ArraySize(closes)-1); i++)
        {
            if(closes[i] > closes[i+1]) up_count++;
            else if(closes[i] < closes[i+1]) down_count++;
        }
        
        m_trend_detected = (up_count > 7 || down_count > 7);
        m_range_detected = (m_fractal_dimension < 1.3 && m_pattern_clarity > 60);
        m_pattern_conflict = (m_trend_detected && m_range_detected);
    }
    
    void ClassifyCognitiveState()
    {
        if(m_pattern_clarity > 70 && m_information_entropy < 40)
            m_cognitive_state = "CLEAR";
        else if(m_pattern_conflict || m_information_entropy > 70)
            m_cognitive_state = "CONFUSED";
        else if(m_pattern_clarity > 50 && m_pattern_clarity < 70)
            m_cognitive_state = "DISCOVERING";
        else
            m_cognitive_state = "CHAOTIC";
    }
    
    string DetectCognitiveTransition()
    {
        static string prev_state = "DISCOVERING";
        
        if(m_cognitive_state != prev_state)
        {
            string transition = prev_state + "_TO_" + m_cognitive_state;
            prev_state = m_cognitive_state;
            return transition;
        }
        
        if(m_pattern_clarity > 70 && GetClarityGradient() > 15)
            return "CLARITY_EMERGING";
        
        if(m_pattern_clarity < 40 && GetClarityGradient() < -15)
            return "CLARITY_BREAKDOWN";
        
        return "STABLE";
    }
    
    double GetClarityGradient()
    {
        if(ArraySize(m_clarity_history) < 5)
            return 0;
        return m_clarity_history[0] - m_clarity_history[4];
    }
    
    void StoreClarity(double clarity)
    {
        for(int i = ArraySize(m_clarity_history) - 1; i > 0; i--)
            m_clarity_history[i] = m_clarity_history[i-1];
        m_clarity_history[0] = clarity;
    }
    
    void StoreEntropy(double entropy)
    {
        for(int i = ArraySize(m_entropy_history) - 1; i > 0; i--)
            m_entropy_history[i] = m_entropy_history[i-1];
        m_entropy_history[0] = entropy;
    }
    
    // Getters - ONLY DECLARED ONCE
    double GetPatternClarity() { return m_pattern_clarity; }
    double GetFractalDimension() { return m_fractal_dimension; }
    double GetInformationEntropy() { return m_information_entropy; }
    double GetSignalToNoise() { return m_signal_to_noise; }
    string GetCognitiveState() { return m_cognitive_state; }
    
    bool IsTradeable()
    {
        return (m_pattern_clarity > 60 && !m_pattern_conflict);
    }
    
    double GetConfidenceMultiplier()
    {
        if(m_pattern_clarity > 80) return 1.2;
        if(m_pattern_clarity < 40 || m_pattern_conflict) return 0.5;
        return 1.0;
    }
};