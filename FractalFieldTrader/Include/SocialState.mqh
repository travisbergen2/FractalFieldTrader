//+------------------------------------------------------------------+
//| SocialState.mqh                                                  |
//| Market Consensus & Social Coherence Detection                    |
//| Measures collective market behavior                             |
//+------------------------------------------------------------------+

class CSocialState
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_period;
    
    // Related currency pairs for correlation
    string m_related_pairs[];
    
    // Social measurements
    double m_market_consensus;     // 0-100: Agreement level
    double m_correlation_strength; // 0-100: Cross-market alignment
    double m_breadth_indicator;    // 0-100: Participation level
    double m_divergence_index;     // 0-100: Conflict between markets
    
    // Risk sentiment
    string m_risk_mode;            // RISK_ON, RISK_OFF, NEUTRAL
    double m_institutional_flow;   // -100 to +100: Buy/sell pressure
    
    // Historical tracking
    double m_consensus_history[];
    double m_correlation_history[];
    
    // Social regime
    string m_social_state;         // ALIGNED, DIVIDED, DISCOVERING, CHAOTIC
    
public:
    CSocialState(int period = 50)
    {
        m_period = period;
        
        ArrayResize(m_consensus_history, 100);
        ArrayResize(m_correlation_history, 100);
        ArrayInitialize(m_consensus_history, 0);
        ArrayInitialize(m_correlation_history, 0);
        
        m_market_consensus = 50;
        m_correlation_strength = 50;
        m_breadth_indicator = 50;
        m_divergence_index = 50;
        
        m_risk_mode = "NEUTRAL";
        m_institutional_flow = 0;
        m_social_state = "DISCOVERING";
        
        // Setup related pairs for correlation analysis
        SetupRelatedPairs();
    }
    
    //+------------------------------------------------------------------+
    //| Setup related currency pairs                                     |
    //+------------------------------------------------------------------+
    void SetupRelatedPairs()
    {
        // For EURUSD, track related majors
        ArrayResize(m_related_pairs, 4);
        m_related_pairs[0] = "GBPUSD";
        m_related_pairs[1] = "USDJPY";
        m_related_pairs[2] = "USDCHF";
        m_related_pairs[3] = "AUDUSD";
    }
    
    //+------------------------------------------------------------------+
    //| Initialize                                                        |
    //+------------------------------------------------------------------+
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        // Adjust related pairs based on symbol
        if(symbol == "EURUSD")
            SetupRelatedPairs();  // Already set up for EURUSD
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate social coherence                                       |
    //+------------------------------------------------------------------+
    double Calculate()
    {
        // Get primary pair data
        double closes[];
        ArraySetAsSeries(closes, true);
        
        if(CopyClose(m_symbol, m_timeframe, 0, m_period, closes) < m_period)
            return 50.0;
        
        // Calculate correlation with related pairs
        CalculateCorrelations(closes);
        
        // Calculate market consensus
        CalculateConsensus(closes);
        
        // Detect risk mode
        DetectRiskMode();
        
        // Calculate breadth
        CalculateBreadth();
        
        // Classify social state
        ClassifySocialState();
        
        // Calculate social coherence
        // High coherence = strong consensus + aligned correlations
        
        double coherence = 0;
        
        // Consensus component (40%)
        coherence += m_market_consensus * 0.4;
        
        // Correlation strength component (30%)
        coherence += m_correlation_strength * 0.3;
        
        // Breadth component (30%)
        coherence += m_breadth_indicator * 0.3;
        
        // Penalty for divergence
        if(m_divergence_index > 60)
            coherence *= 0.7;
        
        return MathMax(0, MathMin(100, coherence));
    }
    
    //+------------------------------------------------------------------+
    //| Calculate correlations with related pairs                        |
    //+------------------------------------------------------------------+
    void CalculateCorrelations(double &base_closes[])
    {
        double total_correlation = 0;
        int valid_correlations = 0;
        
        for(int p = 0; p < ArraySize(m_related_pairs); p++)
        {
            double related_closes[];
            ArraySetAsSeries(related_closes, true);
            
            // Try to get data for related pair
            if(CopyClose(m_related_pairs[p], m_timeframe, 0, m_period, related_closes) >= m_period)
            {
                double corr = CalculateCorrelation(base_closes, related_closes);
                total_correlation += MathAbs(corr);  // Absolute correlation strength
                valid_correlations++;
            }
        }
        
        if(valid_correlations > 0)
            m_correlation_strength = (total_correlation / valid_correlations) * 100;
        else
            m_correlation_strength = 50;  // Neutral if no data
        
        StoreCorrelation(m_correlation_strength);
    }
    
    //+------------------------------------------------------------------+
    //| Calculate Pearson correlation coefficient                        |
    //+------------------------------------------------------------------+
    double CalculateCorrelation(double &x[], double &y[])
    {
        int n = MathMin(ArraySize(x), ArraySize(y));
        if(n < 10) return 0;
        
        n = MathMin(n, 30);  // Use last 30 bars max
        
        // Calculate means
        double mean_x = 0, mean_y = 0;
        for(int i = 0; i < n; i++)
        {
            mean_x += x[i];
            mean_y += y[i];
        }
        mean_x /= n;
        mean_y /= n;
        
        // Calculate correlation
        double numerator = 0;
        double sum_sq_x = 0;
        double sum_sq_y = 0;
        
        for(int i = 0; i < n; i++)
        {
            double dx = x[i] - mean_x;
            double dy = y[i] - mean_y;
            numerator += dx * dy;
            sum_sq_x += dx * dx;
            sum_sq_y += dy * dy;
        }
        
        double denominator = MathSqrt(sum_sq_x * sum_sq_y);
        
        if(denominator == 0) return 0;
        
        return numerator / denominator;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate market consensus (directional agreement)               |
    //+------------------------------------------------------------------+
    void CalculateConsensus(double &closes[])
    {
        // Measure how consistent the direction is
        
        int up_bars = 0;
        int down_bars = 0;
        int neutral_bars = 0;
        
        for(int i = 0; i < MathMin(20, ArraySize(closes)-1); i++)
        {
            double change = closes[i] - closes[i+1];
            double pct_change = (closes[i+1] != 0) ? (change / closes[i+1]) : 0;
            
            if(MathAbs(pct_change) < 0.0001)  // Less than 0.01% = neutral
                neutral_bars++;
            else if(change > 0)
                up_bars++;
            else
                down_bars++;
        }
        
        // Consensus = how much majority agrees
        int total = up_bars + down_bars + neutral_bars;
        if(total == 0)
        {
            m_market_consensus = 50;
            return;
        }
        
        int majority = MathMax(up_bars, MathMax(down_bars, neutral_bars));
        m_market_consensus = ((double)majority / total) * 100;
        
        StoreConsensus(m_market_consensus);
    }
    
    //+------------------------------------------------------------------+
    //| Detect risk-on vs risk-off mode                                  |
    //+------------------------------------------------------------------+
    void DetectRiskMode()
    {
        // Simplified risk detection based on pair behavior
        // In real implementation, would check USD strength, JPY, gold, etc.
        
        double closes[];
        ArraySetAsSeries(closes, true);
        
        if(CopyClose(m_symbol, m_timeframe, 0, 10, closes) < 10)
        {
            m_risk_mode = "NEUTRAL";
            return;
        }
        
        // Calculate momentum
        double recent_change = closes[0] - closes[9];
        double avg_price = 0;
        for(int i = 0; i < 10; i++)
            avg_price += closes[i];
        avg_price /= 10;
        
        double momentum = (avg_price != 0) ? (recent_change / avg_price) : 0;
        
        // Check volatility
        double volatility = 0;
        for(int i = 0; i < 9; i++)
        {
            double change = closes[i] - closes[i+1];
            volatility += MathAbs(change);
        }
        volatility /= 9;
        
        // Risk-on: Rising with moderate volatility
        // Risk-off: Falling with high volatility or flight to safety
        
        if(momentum > 0.001 && volatility < avg_price * 0.01)
            m_risk_mode = "RISK_ON";
        else if(momentum < -0.001 && volatility > avg_price * 0.015)
            m_risk_mode = "RISK_OFF";
        else
            m_risk_mode = "NEUTRAL";
    }
    
    //+------------------------------------------------------------------+
    //| Calculate breadth indicator                                      |
    //+------------------------------------------------------------------+
    void CalculateBreadth()
    {
        // Measure how many related pairs are moving together
        
        int aligned_pairs = 0;
        int total_pairs = 0;
        
        // Get primary pair direction
        double closes[];
        ArraySetAsSeries(closes, true);
        
        if(CopyClose(m_symbol, m_timeframe, 0, 5, closes) < 5)
        {
            m_breadth_indicator = 50;
            return;
        }
        
        bool primary_up = (closes[0] > closes[4]);
        
        // Check related pairs
        for(int p = 0; p < ArraySize(m_related_pairs); p++)
        {
            double related_closes[];
            ArraySetAsSeries(related_closes, true);
            
            if(CopyClose(m_related_pairs[p], m_timeframe, 0, 5, related_closes) >= 5)
            {
                bool related_up = (related_closes[0] > related_closes[4]);
                
                // Check if moving in same direction (considering correlation)
                // For inverse pairs like USDJPY vs EURUSD, this would need adjustment
                if(related_up == primary_up)
                    aligned_pairs++;
                
                total_pairs++;
            }
        }
        
        if(total_pairs > 0)
            m_breadth_indicator = ((double)aligned_pairs / total_pairs) * 100;
        else
            m_breadth_indicator = 50;
        
        // Calculate divergence (opposite of breadth)
        m_divergence_index = 100 - m_breadth_indicator;
    }
    
    //+------------------------------------------------------------------+
    //| Classify social state                                            |
    //+------------------------------------------------------------------+
    void ClassifySocialState()
    {
        // ALIGNED: High consensus + strong correlations + good breadth
        if(m_market_consensus > 70 && m_correlation_strength > 60 && m_breadth_indicator > 60)
        {
            m_social_state = "ALIGNED";
        }
        // DIVIDED: Low consensus + divergence
        else if(m_market_consensus < 40 || m_divergence_index > 70)
        {
            m_social_state = "DIVIDED";
        }
        // DISCOVERING: Moderate consensus, forming alignment
        else if(m_market_consensus > 50 && m_market_consensus < 70)
        {
            m_social_state = "DISCOVERING";
        }
        // CHAOTIC: Low everything
        else
        {
            m_social_state = "CHAOTIC";
        }
    }
    
    //+------------------------------------------------------------------+
    //| Detect social transitions                                        |
    //+------------------------------------------------------------------+
    string DetectSocialTransition()
    {
        static string prev_state = "DISCOVERING";
        
        if(m_social_state != prev_state)
        {
            string transition = prev_state + "_TO_" + m_social_state;
            prev_state = m_social_state;
            return transition;
        }
        
        // Check for consensus building
        if(m_market_consensus > 70 && GetConsensusGradient() > 15)
            return "CONSENSUS_BUILDING";
        
        // Check for consensus breakdown
        if(m_market_consensus < 40 && GetConsensusGradient() < -15)
            return "CONSENSUS_BREAKDOWN";
        
        // Check for risk mode shift
        static string prev_risk = "NEUTRAL";
        if(m_risk_mode != prev_risk)
        {
            string risk_transition = prev_risk + "_TO_" + m_risk_mode;
            prev_risk = m_risk_mode;
            return risk_transition;
        }
        
        return "STABLE";
    }
    
    //+------------------------------------------------------------------+
    //| Get consensus gradient                                           |
    //+------------------------------------------------------------------+
    double GetConsensusGradient()
    {
        if(ArraySize(m_consensus_history) < 5)
            return 0;
        return m_consensus_history[0] - m_consensus_history[4];
    }
    
    //+------------------------------------------------------------------+
    //| Store in history                                                 |
    //+------------------------------------------------------------------+
    void StoreConsensus(double consensus)
    {
        for(int i = ArraySize(m_consensus_history) - 1; i > 0; i--)
            m_consensus_history[i] = m_consensus_history[i-1];
        m_consensus_history[0] = consensus;
    }
    
    void StoreCorrelation(double correlation)
    {
        for(int i = ArraySize(m_correlation_history) - 1; i > 0; i--)
            m_correlation_history[i] = m_correlation_history[i-1];
        m_correlation_history[0] = correlation;
    }
    
    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    double GetMarketConsensus() { return m_market_consensus; }
    double GetCorrelationStrength() { return m_correlation_strength; }
    double GetBreadthIndicator() { return m_breadth_indicator; }
    double GetDivergenceIndex() { return m_divergence_index; }
    string GetRiskMode() { return m_risk_mode; }
    string GetSocialState() { return m_social_state; }
    
    //+------------------------------------------------------------------+
    //| Check if social conditions favor trading                         |
    //+------------------------------------------------------------------+
    bool IsFavorableForTrading()
    {
        // Good conditions: Aligned or discovering consensus
        // Bad conditions: Divided or chaotic
        return (m_social_state == "ALIGNED" || m_social_state == "DISCOVERING");
    }
    
    //+------------------------------------------------------------------+
    //| Get position size adjustment based on social coherence           |
    //+------------------------------------------------------------------+
    double GetSocialMultiplier()
    {
        // Strong alignment = higher confidence
        if(m_social_state == "ALIGNED" && m_correlation_strength > 70)
            return 1.3;
        
        // Divided markets = lower confidence
        if(m_social_state == "DIVIDED" || m_divergence_index > 70)
            return 0.6;
        
        return 1.0;
    }
};