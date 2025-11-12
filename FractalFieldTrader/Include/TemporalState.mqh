//+------------------------------------------------------------------+
//| TemporalState.mqh                                                |
//| Market-Time Awareness & Chronoception Detection                  |
//| Measures market's subjective experience of time                  |
//+------------------------------------------------------------------+

class CTemporalState
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
    // Market-time bar tracking
    int m_tick_bar_size;          // Ticks per bar
    int m_current_tick_count;     // Current bar tick accumulation
    datetime m_bar_start_time;    // When current bar started
    
    // Chronoception measurements
    double m_temporal_compression;  // 0-100: High = time compressed (fast market)
    double m_temporal_drag;         // 0-100: High = time dragging (slow market)
    double m_frame_rate;            // Ticks per clock-minute
    
    // Historical tracking
    double m_frame_rate_history[];
    double m_compression_history[];
    
    // Rhythm detection
    double m_dominant_period;       // Detected cycle length
    double m_rhythm_strength;       // How regular is the rhythm
    
public:
    CTemporalState(int tick_bar_size = 100)
    {
        m_tick_bar_size = tick_bar_size;
        m_current_tick_count = 0;
        m_bar_start_time = 0;
        
        ArrayResize(m_frame_rate_history, 100);
        ArrayResize(m_compression_history, 100);
        ArrayInitialize(m_frame_rate_history, 0);
        ArrayInitialize(m_compression_history, 0);
        
        m_temporal_compression = 50;
        m_temporal_drag = 50;
        m_frame_rate = 0;
        m_dominant_period = 0;
        m_rhythm_strength = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize for symbol/timeframe                                  |
    //+------------------------------------------------------------------+
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_bar_start_time = TimeCurrent();
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Update on each tick - core market-time tracking                  |
    //+------------------------------------------------------------------+
    void OnTick()
    {
        m_current_tick_count++;
        
        // Calculate current frame rate (ticks per minute)
        datetime now = TimeCurrent();
        double minutes_elapsed = (now - m_bar_start_time) / 60.0;
        
        if(minutes_elapsed > 0.1)  // Avoid division by zero
        {
            m_frame_rate = m_current_tick_count / minutes_elapsed;
            StoreFrameRate(m_frame_rate);
        }
        
        // Check if we've completed a market-time bar
        if(m_current_tick_count >= m_tick_bar_size)
        {
            OnMarketTimeBarComplete(minutes_elapsed);
            
            // Reset for next bar
            m_current_tick_count = 0;
            m_bar_start_time = now;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Called when market-time bar completes                            |
    //+------------------------------------------------------------------+
    void OnMarketTimeBarComplete(double clock_time_elapsed)
    {
        // Calculate temporal compression/drag
        // Fast market = many ticks in short time = temporal compression
        // Slow market = few ticks in long time = temporal drag
        
        double expected_time = 5.0;  // Expected minutes per market-bar (baseline)
        
        if(clock_time_elapsed < expected_time)
        {
            // Temporal compression: More happened than "should" in this time
            m_temporal_compression = 50 + (50 * (expected_time - clock_time_elapsed) / expected_time);
            m_temporal_drag = 100 - m_temporal_compression;
        }
        else
        {
            // Temporal drag: Less happened, time felt slow
            m_temporal_drag = 50 + (50 * (clock_time_elapsed - expected_time) / clock_time_elapsed);
            m_temporal_compression = 100 - m_temporal_drag;
        }
        
        // Clamp values
        m_temporal_compression = MathMax(0, MathMin(100, m_temporal_compression));
        m_temporal_drag = MathMax(0, MathMin(100, m_temporal_drag));
        
        StoreCompression(m_temporal_compression);
        
        // Detect rhythm
        DetectRhythm();
    }
    
    //+------------------------------------------------------------------+
    //| Calculate temporal coherence score                               |
    //+------------------------------------------------------------------+
    double Calculate()
    {
        // High coherence = consistent frame rate (predictable time)
        // Low coherence = erratic frame rate (chaotic time)
        
        if(ArraySize(m_frame_rate_history) < 10)
            return 50.0;  // Not enough data
        
        // Calculate stability of frame rate
        double mean_rate = 0;
        int count = 0;
        
        for(int i = 0; i < 20 && i < ArraySize(m_frame_rate_history); i++)
        {
            if(m_frame_rate_history[i] > 0)
            {
                mean_rate += m_frame_rate_history[i];
                count++;
            }
        }
        
        if(count == 0) return 50.0;
        mean_rate /= count;
        
        // Calculate variance
        double variance = 0;
        for(int i = 0; i < count; i++)
        {
            double diff = m_frame_rate_history[i] - mean_rate;
            variance += diff * diff;
        }
        variance /= count;
        
        double std_dev = MathSqrt(variance);
        
        // Coefficient of variation
        double cv = (mean_rate > 0) ? (std_dev / mean_rate) : 1.0;
        
        // Convert to coherence score (low CV = high coherence)
        double coherence = 100 / (1 + cv);
        
        return MathMax(0, MathMin(100, coherence));
    }
    
    //+------------------------------------------------------------------+
    //| Detect rhythm/cycle in frame rate                                |
    //+------------------------------------------------------------------+
    void DetectRhythm()
    {
        // Simple autocorrelation to find dominant period
        int max_lag = 20;
        double best_correlation = 0;
        int best_lag = 0;
        
        for(int lag = 2; lag < max_lag; lag++)
        {
            double correlation = CalculateAutocorrelation(m_frame_rate_history, lag);
            
            if(correlation > best_correlation)
            {
                best_correlation = correlation;
                best_lag = lag;
            }
        }
        
        m_dominant_period = best_lag;
        m_rhythm_strength = best_correlation * 100;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate autocorrelation at given lag                           |
    //+------------------------------------------------------------------+
    double CalculateAutocorrelation(double &data[], int lag)
    {
        int n = ArraySize(data);
        if(n < lag + 10) return 0;
        
        double mean = 0;
        int count = MathMin(30, n);
        
        for(int i = 0; i < count; i++)
            mean += data[i];
        mean /= count;
        
        double numerator = 0;
        double denominator = 0;
        
        for(int i = 0; i < count - lag; i++)
        {
            double x = data[i] - mean;
            double y = data[i + lag] - mean;
            numerator += x * y;
            denominator += x * x;
        }
        
        return (denominator > 0) ? (numerator / denominator) : 0;
    }
    
    //+------------------------------------------------------------------+
    //| Detect state transitions                                         |
    //+------------------------------------------------------------------+
    string DetectTemporalTransition()
    {
        // Analyze recent history for state changes
        
        // Check for compression spike (market acceleration)
        if(m_temporal_compression > 75 && GetCompressionGradient() > 10)
            return "ACCELERATING";  // Time compressing rapidly
        
        // Check for drag increase (market deceleration)
        if(m_temporal_drag > 75 && GetCompressionGradient() < -10)
            return "DECELERATING";  // Time dragging
        
        // Check for rhythm emergence
        if(m_rhythm_strength > 60)
            return "RHYTHMIC";  // Regular cycles detected
        
        // Check for rhythm breakdown
        if(m_rhythm_strength < 20 && GetPreviousRhythmStrength() > 50)
            return "ARRHYTHMIC";  // Lost rhythm
        
        return "STABLE";
    }
    
    //+------------------------------------------------------------------+
    //| Get compression gradient (rate of change)                        |
    //+------------------------------------------------------------------+
    double GetCompressionGradient()
    {
        if(ArraySize(m_compression_history) < 5)
            return 0;
        
        double recent = m_compression_history[0];
        double past = m_compression_history[4];
        
        return recent - past;
    }
    
    //+------------------------------------------------------------------+
    //| Get previous rhythm strength                                     |
    //+------------------------------------------------------------------+
    double GetPreviousRhythmStrength()
    {
        // Would need to track rhythm history - simplified for now
        return m_rhythm_strength;
    }
    
    //+------------------------------------------------------------------+
    //| Store frame rate in history                                      |
    //+------------------------------------------------------------------+
    void StoreFrameRate(double rate)
    {
        for(int i = ArraySize(m_frame_rate_history) - 1; i > 0; i--)
            m_frame_rate_history[i] = m_frame_rate_history[i-1];
        
        m_frame_rate_history[0] = rate;
    }
    
    //+------------------------------------------------------------------+
    //| Store compression in history                                     |
    //+------------------------------------------------------------------+
    void StoreCompression(double compression)
    {
        for(int i = ArraySize(m_compression_history) - 1; i > 0; i--)
            m_compression_history[i] = m_compression_history[i-1];
        
        m_compression_history[0] = compression;
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetTemporalCompression() { return m_temporal_compression; }
    double GetTemporalDrag() { return m_temporal_drag; }
    double GetFrameRate() { return m_frame_rate; }
    double GetDominantPeriod() { return m_dominant_period; }
    double GetRhythmStrength() { return m_rhythm_strength; }
    
    //+------------------------------------------------------------------+
    //| Get temporal efficiency (like your book's measure)               |
    //+------------------------------------------------------------------+
    double GetTemporalEfficiency()
    {
        // High efficiency = temporal compression (lots happening fast)
        // Low efficiency = temporal drag (little happening slow)
        
        return m_temporal_compression;
    }
    
    //+------------------------------------------------------------------+
    //| Check if market is in flow state (from temporal perspective)     |
    //+------------------------------------------------------------------+
    bool IsInFlowState()
    {
        // Flow = temporal compression + rhythm
        return (m_temporal_compression > 65 && m_rhythm_strength > 40);
    }
    
    //+------------------------------------------------------------------+
    //| Check if market is in chaos state                                |
    //+------------------------------------------------------------------+
    bool IsInChaosState()
    {
        // Chaos = erratic frame rate + no rhythm
        double coherence = Calculate();
        return (coherence < 35 && m_rhythm_strength < 20);
    }
};