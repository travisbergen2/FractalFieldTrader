//+------------------------------------------------------------------+
//| MLPredictor.mqh - ML-based trade gating with rolling accuracy   |
//+------------------------------------------------------------------+
#ifndef __ML_PREDICTOR_MQH__
#define __ML_PREDICTOR_MQH__

//+------------------------------------------------------------------+
//| Trade outcome for tracking                                       |
//+------------------------------------------------------------------+
struct STradeOutcome
{
    datetime time;
    double predicted_prob;
    int predicted_direction;  // 1 = long, -1 = short
    bool was_correct;
    double pnl;
};

//+------------------------------------------------------------------+
//| ML Predictor with rolling accuracy tracking                      |
//+------------------------------------------------------------------+
class CMLPredictor
{
private:
    double m_enter_threshold;   // Enter trade if prob >= this
    double m_stop_threshold;    // Stop trading if rolling acc < this
    int m_rolling_window;       // Window size for rolling accuracy

    STradeOutcome m_outcomes[];
    int m_total_predictions;
    int m_correct_predictions;

    bool m_trading_enabled;
    string m_model_file;

    // Simple decision tree weights (will be replaced by trained model)
    double m_weights[];
    double m_bias;
    bool m_model_loaded;

public:
    CMLPredictor()
    {
        m_enter_threshold = 0.75;  // 75% probability to enter
        m_stop_threshold = 0.60;   // Stop if accuracy < 60%
        m_rolling_window = 20;     // Last 20 trades

        ArrayResize(m_outcomes, 0);
        m_total_predictions = 0;
        m_correct_predictions = 0;
        m_trading_enabled = true;
        m_model_loaded = false;
        m_bias = 0.0;

        ArrayResize(m_weights, 11);  // 11 features from FPF
        ArrayInitialize(m_weights, 0.1);  // Default uniform weights
    }

    ~CMLPredictor() {}

    void Configure(double enter_threshold, double stop_threshold, int rolling_window)
    {
        m_enter_threshold = enter_threshold;
        m_stop_threshold = stop_threshold;
        m_rolling_window = rolling_window;
    }

    // Load model from file (simple format: one weight per line, last line = bias)
    bool LoadModel(string filename)
    {
        m_model_file = filename;
        int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);

        if(handle == INVALID_HANDLE)
        {
            Print("⚠️  ML Model file not found: ", filename);
            Print("   Using default uniform weights until model is trained");
            return false;
        }

        // Read weights
        for(int i = 0; i < 11 && !FileIsEnding(handle); i++)
        {
            string line = FileReadString(handle);
            m_weights[i] = StringToDouble(line);
        }

        // Read bias
        if(!FileIsEnding(handle))
        {
            string line = FileReadString(handle);
            m_bias = StringToDouble(line);
        }

        FileClose(handle);
        m_model_loaded = true;
        Print("✅ ML Model loaded: ", filename);
        return true;
    }

    // Predict probability of profitable trade (simple logistic regression)
    double PredictProbability(const double &features[])
    {
        if(ArraySize(features) != 11)
        {
            Print("❌ ERROR: Feature vector size mismatch");
            return 0.5;
        }

        // Linear combination
        double z = m_bias;
        for(int i = 0; i < 11; i++)
            z += m_weights[i] * features[i];

        // Sigmoid
        double prob = 1.0 / (1.0 + MathExp(-z));

        return prob;
    }

    // Check if we should enter trade based on prediction
    bool ShouldEnterTrade(const double &features[], int direction, double &out_probability)
    {
        if(!m_trading_enabled)
        {
            out_probability = 0.0;
            return false;
        }

        out_probability = PredictProbability(features);

        // Log prediction
        m_total_predictions++;

        return (out_probability >= m_enter_threshold);
    }

    // Record trade outcome and update rolling accuracy
    void RecordOutcome(datetime time, double predicted_prob, int predicted_direction,
                      bool was_correct, double pnl)
    {
        STradeOutcome outcome;
        outcome.time = time;
        outcome.predicted_prob = predicted_prob;
        outcome.predicted_direction = predicted_direction;
        outcome.was_correct = was_correct;
        outcome.pnl = pnl;

        int idx = ArraySize(m_outcomes);
        ArrayResize(m_outcomes, idx + 1);
        m_outcomes[idx] = outcome;

        if(was_correct)
            m_correct_predictions++;

        // Check rolling accuracy
        double rolling_acc = GetRollingAccuracy();

        Print("📊 Trade outcome: ", was_correct ? "✅ CORRECT" : "❌ WRONG",
              " | PnL: ", DoubleToString(pnl, 2),
              " | Prob: ", DoubleToString(predicted_prob, 3),
              " | Rolling Acc: ", DoubleToString(rolling_acc * 100, 1), "%");

        // Auto-disable if accuracy drops
        if(rolling_acc < m_stop_threshold && ArraySize(m_outcomes) >= m_rolling_window)
        {
            m_trading_enabled = false;
            Print("🛑 TRADING DISABLED - Rolling accuracy (", DoubleToString(rolling_acc * 100, 1),
                  "%) below threshold (", DoubleToString(m_stop_threshold * 100, 1), "%)");
            Print("   Collect more data and retrain model to resume trading");
        }
    }

    // Get rolling accuracy over last N trades
    double GetRollingAccuracy() const
    {
        int n = ArraySize(m_outcomes);
        if(n == 0) return 1.0;  // No trades yet, assume perfect

        int start = MathMax(0, n - m_rolling_window);
        int correct = 0;

        for(int i = start; i < n; i++)
        {
            if(m_outcomes[i].was_correct)
                correct++;
        }

        return (double)correct / (n - start);
    }

    // Get overall accuracy
    double GetOverallAccuracy() const
    {
        if(m_total_predictions == 0) return 1.0;
        return (double)m_correct_predictions / m_total_predictions;
    }

    // Get stats
    int GetTotalPredictions() const { return m_total_predictions; }
    int GetCorrectPredictions() const { return m_correct_predictions; }
    bool IsTradingEnabled() const { return m_trading_enabled; }
    bool IsModelLoaded() const { return m_model_loaded; }

    // Manual enable/disable
    void EnableTrading() { m_trading_enabled = true; }
    void DisableTrading() { m_trading_enabled = false; }

    // Print statistics
    void PrintStats() const
    {
        Print("=== ML Predictor Statistics ===");
        Print("  Model loaded: ", m_model_loaded ? "YES" : "NO (using defaults)");
        Print("  Trading enabled: ", m_trading_enabled ? "YES" : "NO");
        Print("  Total predictions: ", m_total_predictions);
        Print("  Overall accuracy: ", DoubleToString(GetOverallAccuracy() * 100, 1), "%");
        Print("  Rolling accuracy: ", DoubleToString(GetRollingAccuracy() * 100, 1), "%");
        Print("  Enter threshold: ", DoubleToString(m_enter_threshold * 100, 1), "%");
        Print("  Stop threshold: ", DoubleToString(m_stop_threshold * 100, 1), "%");
    }
};

#endif // __ML_PREDICTOR_MQH__
