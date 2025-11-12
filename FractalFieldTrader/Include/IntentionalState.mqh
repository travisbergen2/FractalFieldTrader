//+------------------------------------------------------------------+
//| IntentionalState.mqh                                             |
//| Buy/Sell Pressure & Directional Intent Detection                 |
//| Measures market's intentional direction via volume               |
//+------------------------------------------------------------------+

class CIntentionalState
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_period;
    
    double m_buy_pressure;
    double m_sell_pressure;
    double m_obv;
    double m_volume_momentum;
    
    double m_obv_history[];
    double m_pressure_history[];
    
    string m_intent;
    
public:
    CIntentionalState(int period = 50)
    {
        m_period = period;
        
        ArrayResize(m_obv_history, 100);
        ArrayResize(m_pressure_history, 100);
        ArrayInitialize(m_obv_history, 0);
        ArrayInitialize(m_pressure_history, 0);
        
        m_buy_pressure = 50;
        m_sell_pressure = 50;
        m_obv = 0;
        m_volume_momentum = 0;
        m_intent = "NEUTRAL";
    }
    
    bool Init(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        return true;
    }
    
    double Calculate()
    {
        CalculateOBV();
        CalculatePressure();
        CalculateVolumeMomentum();
        ClassifyIntent();
        
        double pressure_diff = MathAbs(m_buy_pressure - 50);
        double coherence = pressure_diff * 2;
        
        return MathMax(0, MathMin(100, coherence));
    }
    
    void CalculateOBV()
    {
        double closes[];
        long volumes[];
        
        ArraySetAsSeries(closes, true);
        ArraySetAsSeries(volumes, true);
        
        if(CopyClose(m_symbol, m_timeframe, 0, m_period, closes) < m_period ||
           CopyTickVolume(m_symbol, m_timeframe, 0, m_period, volumes) < m_period)
        {
            return;
        }
        
        double obv = 0;
        for(int i = m_period - 1; i > 0; i--)
        {
            if(closes[i-1] > closes[i])
                obv += volumes[i-1];
            else if(closes[i-1] < closes[i])
                obv -= volumes[i-1];
        }
        
        m_obv = obv;
        StoreOBV(obv);
    }
    
    void CalculatePressure()
    {
        double opens[];
        double closes[];
        double highs[];
        double lows[];
        long volumes[];
        
        ArraySetAsSeries(opens, true);
        ArraySetAsSeries(closes, true);
        ArraySetAsSeries(highs, true);
        ArraySetAsSeries(lows, true);
        ArraySetAsSeries(volumes, true);
        
        int bars = MathMin(20, m_period);
        
        if(CopyOpen(m_symbol, m_timeframe, 0, bars, opens) < bars ||
           CopyClose(m_symbol, m_timeframe, 0, bars, closes) < bars ||
           CopyHigh(m_symbol, m_timeframe, 0, bars, highs) < bars ||
           CopyLow(m_symbol, m_timeframe, 0, bars, lows) < bars ||
           CopyTickVolume(m_symbol, m_timeframe, 0, bars, volumes) < bars)
        {
            m_buy_pressure = 50;
            m_sell_pressure = 50;
            return;
        }
        
        double buy_volume = 0;
        double sell_volume = 0;
        
        for(int i = 0; i < bars; i++)
        {
            double range = highs[i] - lows[i];
            if(range == 0) continue;
            
            double close_position = (closes[i] - lows[i]) / range;
            
            if(closes[i] > opens[i])
            {
                buy_volume += volumes[i] * close_position;
                sell_volume += volumes[i] * (1 - close_position);
            }
            else if(closes[i] < opens[i])
            {
                sell_volume += volumes[i] * (1 - close_position);
                buy_volume += volumes[i] * close_position;
            }
            else
            {
                buy_volume += volumes[i] * 0.5;
                sell_volume += volumes[i] * 0.5;
            }
        }
        
        double total_volume = buy_volume + sell_volume;
        if(total_volume > 0)
        {
            m_buy_pressure = (buy_volume / total_volume) * 100;
            m_sell_pressure = (sell_volume / total_volume) * 100;
        }
        else
        {
            m_buy_pressure = 50;
            m_sell_pressure = 50;
        }
        
        StorePressure(m_buy_pressure);
    }
    
    void CalculateVolumeMomentum()
    {
        long volumes[];
        ArraySetAsSeries(volumes, true);
        
        if(CopyTickVolume(m_symbol, m_timeframe, 0, 10, volumes) < 10)
        {
            m_volume_momentum = 0;
            return;
        }
        
        double recent_avg = 0;
        double past_avg = 0;
        
        for(int i = 0; i < 5; i++)
            recent_avg += volumes[i];
        recent_avg /= 5;
        
        for(int i = 5; i < 10; i++)
            past_avg += volumes[i];
        past_avg /= 5;
        
        if(past_avg > 0)
            m_volume_momentum = ((recent_avg - past_avg) / past_avg) * 100;
        else
            m_volume_momentum = 0;
    }
    
    void ClassifyIntent()
    {
        if(m_buy_pressure > 60)
            m_intent = "BUYING";
        else if(m_sell_pressure > 60)
            m_intent = "SELLING";
        else
            m_intent = "NEUTRAL";
    }
    
    string DetectIntentTransition()
    {
        static string prev_intent = "NEUTRAL";
        
        if(m_intent != prev_intent)
        {
            string transition = prev_intent + "_TO_" + m_intent;
            prev_intent = m_intent;
            return transition;
        }
        
        if(m_volume_momentum > 50)
            return "VOLUME_SURGE";
        
        return "STABLE";
    }
    
    void StoreOBV(double obv)
    {
        for(int i = ArraySize(m_obv_history) - 1; i > 0; i--)
            m_obv_history[i] = m_obv_history[i-1];
        m_obv_history[0] = obv;
    }
    
    void StorePressure(double pressure)
    {
        for(int i = ArraySize(m_pressure_history) - 1; i > 0; i--)
            m_pressure_history[i] = m_pressure_history[i-1];
        m_pressure_history[0] = pressure;
    }
    
    double GetBuyPressure() { return m_buy_pressure; }
    double GetSellPressure() { return m_sell_pressure; }
    double GetOBV() { return m_obv; }
    double GetVolumeMomentum() { return m_volume_momentum; }
    string GetIntent() { return m_intent; }
    
    bool SupportsLong()
    {
        return (m_intent == "BUYING" || m_buy_pressure > 55);
    }
    
    bool SupportsShort()
    {
        return (m_intent == "SELLING" || m_sell_pressure > 55);
    }
};