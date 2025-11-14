//+------------------------------------------------------------------+
//| FPF_StateEngine.mqh                                               |
//| Fractal Pattern Field State Engine                                |
//| Shared module for 5-axis FPF state calculation and regime detect  |
//+------------------------------------------------------------------+
#property copyright "FPF State Engine v1.0"
#property strict

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                         |
//+------------------------------------------------------------------+
enum MarketRegime
{
   REGIME_NONE = 0,           // Mixed/unclear signals
   REGIME_TREND_UP,           // Strong uptrend (P > 0.3, E > 0.1)
   REGIME_TREND_DOWN,         // Strong downtrend (P < -0.3, E < -0.1)
   REGIME_REVERSAL_UP,        // Reversal to upside (P < -0.1, N > 0, A > 0)
   REGIME_REVERSAL_DOWN,      // Reversal to downside (P > 0.1, N < 0, A < 0)
   REGIME_CHOP                // Choppy/ranging (|P| < 0.15, |E| < 0.15)
};

//+------------------------------------------------------------------+
//| FPF State Engine Class                                            |
//+------------------------------------------------------------------+
class CFPFStateEngine
{
private:
   // Symbol and timeframe
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   // FPF State Vector [P, E, N, A, C]
   double m_FPF_State[5];        // Smoothed state
   double m_FPF_StateRaw[5];     // Raw calculated values
   double m_FPF_StatePrev[5];    // Previous values for momentum

   // Regime
   MarketRegime m_CurrentRegime;

   // Smoothing parameters
   double m_mu;         // Smoothing factor from half-life
   double m_lambda;     // Adaptive smoothing weight

   // Configuration
   int m_BaseWindow;
   int m_HalfLife;
   double m_TrapThreshold;

   // Indicator handles
   int m_ATR_Handle;
   int m_EMA_Fast_Handle;
   int m_EMA_Slow_Handle;

   // Rotation metrics
   double m_SpotX;
   double m_SpotY;
   double m_RotationVelocity;
   double m_RotationAngle;
   double m_OrbitalEnergy;
   double m_ResonanceEnergy;

   // Previous spot for rotation calculation
   double m_PrevSpotX;
   double m_PrevSpotY;

   // Initialization flag
   bool m_Initialized;

   // Private calculation methods
   double CalculateP();    // Perception (trend efficiency)
   double CalculateE();    // Emotion (bull vs bear pressure)
   double CalculateN();    // Narrative (liquidity distribution)
   double CalculateA();    // Alignment (sweep direction)
   double CalculateC();    // Coherence (trap detection)

   void ApplySmoothing();
   void DetectRegimeInternal();

public:
   // Constructor/Destructor
   CFPFStateEngine();
   ~CFPFStateEngine();

   // Initialization
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int baseWindow, int halfLife, double trapThreshold);
   void Deinit();

   // Main calculation
   void CalculateState();
   void UpdateRotationMetrics();
   MarketRegime DetectRegime();

   // Getters - FPF Axes
   double GetP() { return m_FPF_State[0]; }
   double GetE() { return m_FPF_State[1]; }
   double GetN() { return m_FPF_State[2]; }
   double GetA() { return m_FPF_State[3]; }
   double GetC() { return m_FPF_State[4]; }

   // Getters - Raw values
   double GetPRaw() { return m_FPF_StateRaw[0]; }
   double GetERaw() { return m_FPF_StateRaw[1]; }
   double GetNRaw() { return m_FPF_StateRaw[2]; }
   double GetARaw() { return m_FPF_StateRaw[3]; }
   double GetCRaw() { return m_FPF_StateRaw[4]; }

   // Getters - Regime
   MarketRegime GetRegime() { return m_CurrentRegime; }
   string GetRegimeString();

   // Getters - Rotation metrics
   double GetSpotX() { return m_SpotX; }
   double GetSpotY() { return m_SpotY; }
   double GetRotationVelocity() { return m_RotationVelocity; }
   double GetRotationAngle() { return m_RotationAngle; }
   double GetOrbitalEnergy() { return m_OrbitalEnergy; }
   double GetResonanceEnergy() { return m_ResonanceEnergy; }

   // Status
   bool IsInitialized() { return m_Initialized; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CFPFStateEngine::CFPFStateEngine()
{
   m_Initialized = false;
   m_symbol = "";
   m_timeframe = PERIOD_CURRENT;
   m_ATR_Handle = INVALID_HANDLE;
   m_EMA_Fast_Handle = INVALID_HANDLE;
   m_EMA_Slow_Handle = INVALID_HANDLE;

   ArrayInitialize(m_FPF_State, 0.0);
   ArrayInitialize(m_FPF_StateRaw, 0.0);
   ArrayInitialize(m_FPF_StatePrev, 0.0);

   m_CurrentRegime = REGIME_NONE;
   m_mu = 0.1;
   m_lambda = 0.5;

   m_SpotX = 0.0;
   m_SpotY = 0.0;
   m_PrevSpotX = 0.0;
   m_PrevSpotY = 0.0;
   m_RotationVelocity = 0.0;
   m_RotationAngle = 0.0;
   m_OrbitalEnergy = 0.0;
   m_ResonanceEnergy = 0.0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CFPFStateEngine::~CFPFStateEngine()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize FPF State Engine                                       |
//+------------------------------------------------------------------+
bool CFPFStateEngine::Init(string symbol, ENUM_TIMEFRAMES tf, int baseWindow, int halfLife, double trapThreshold)
{
   m_symbol = symbol;
   m_timeframe = tf;
   m_BaseWindow = baseWindow;
   m_HalfLife = halfLife;
   m_TrapThreshold = trapThreshold;

   // Calculate smoothing parameters
   // mu = 1 - exp(-ln(2) / halfLife)
   m_mu = 1.0 - MathExp(-0.693147 / (double)m_HalfLife);
   m_lambda = 0.5; // Fixed for now, could be adaptive

   // Create indicator handles
   m_ATR_Handle = iATR(m_symbol, m_timeframe, 14);
   m_EMA_Fast_Handle = iMA(m_symbol, m_timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
   m_EMA_Slow_Handle = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(m_ATR_Handle == INVALID_HANDLE ||
      m_EMA_Fast_Handle == INVALID_HANDLE ||
      m_EMA_Slow_Handle == INVALID_HANDLE)
   {
      Print("FPF_StateEngine: Failed to create indicator handles for ", m_symbol);
      return false;
   }

   m_Initialized = true;
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize and release resources                               |
//+------------------------------------------------------------------+
void CFPFStateEngine::Deinit()
{
   if(m_ATR_Handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_ATR_Handle);
      m_ATR_Handle = INVALID_HANDLE;
   }

   if(m_EMA_Fast_Handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_EMA_Fast_Handle);
      m_EMA_Fast_Handle = INVALID_HANDLE;
   }

   if(m_EMA_Slow_Handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_EMA_Slow_Handle);
      m_EMA_Slow_Handle = INVALID_HANDLE;
   }

   m_Initialized = false;
}

//+------------------------------------------------------------------+
//| Calculate P-Axis (Perception - Trend Efficiency)                 |
//| P = (net_move / path_length) normalized to [-1, +1]              |
//+------------------------------------------------------------------+
double CFPFStateEngine::CalculateP()
{
   if(!m_Initialized) return 0.0;

   double close[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int copied = CopyClose(m_symbol, m_timeframe, 0, m_BaseWindow + 1, close);
   if(copied < m_BaseWindow + 1) return 0.0;

   CopyHigh(m_symbol, m_timeframe, 0, m_BaseWindow + 1, high);
   CopyLow(m_symbol, m_timeframe, 0, m_BaseWindow + 1, low);

   // Net move from oldest to newest
   double net_move = close[0] - close[m_BaseWindow];

   // Path length = sum of all bar ranges
   double path_length = 0.0;
   for(int i = 0; i < m_BaseWindow; i++)
   {
      path_length += MathAbs(close[i] - close[i + 1]);
   }

   if(path_length == 0.0) return 0.0;

   // Efficiency ratio: -1 to +1
   double P = net_move / path_length;

   // Clamp to [-1, 1]
   return MathMax(-1.0, MathMin(1.0, P));
}

//+------------------------------------------------------------------+
//| Calculate E-Axis (Emotion - Bull vs Bear Pressure)               |
//| E = (cumulative_bull_bodies - cumulative_bear_bodies) normalized |
//+------------------------------------------------------------------+
double CFPFStateEngine::CalculateE()
{
   if(!m_Initialized) return 0.0;

   double open[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);

   int copied = CopyOpen(m_symbol, m_timeframe, 0, m_BaseWindow, open);
   if(copied < m_BaseWindow) return 0.0;

   CopyClose(m_symbol, m_timeframe, 0, m_BaseWindow, close);

   double bull_pressure = 0.0;
   double bear_pressure = 0.0;

   for(int i = 0; i < m_BaseWindow; i++)
   {
      double body = close[i] - open[i];
      if(body > 0)
         bull_pressure += body;
      else
         bear_pressure += MathAbs(body);
   }

   double total_pressure = bull_pressure + bear_pressure;
   if(total_pressure == 0.0) return 0.0;

   // Normalize to [-1, +1]
   double E = (bull_pressure - bear_pressure) / total_pressure;

   return MathMax(-1.0, MathMin(1.0, E));
}

//+------------------------------------------------------------------+
//| Calculate N-Axis (Narrative - Liquidity Distribution)            |
//| N = weighted liquidity above vs below current price using swings |
//+------------------------------------------------------------------+
double CFPFStateEngine::CalculateN()
{
   if(!m_Initialized) return 0.0;

   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int copied = CopyHigh(m_symbol, m_timeframe, 0, m_BaseWindow, high);
   if(copied < m_BaseWindow) return 0.0;

   CopyLow(m_symbol, m_timeframe, 0, m_BaseWindow, low);
   CopyClose(m_symbol, m_timeframe, 0, m_BaseWindow, close);

   double current_price = close[0];
   double liquidity_above = 0.0;
   double liquidity_below = 0.0;

   // Simple swing detection: local highs and lows
   for(int i = 1; i < m_BaseWindow - 1; i++)
   {
      // Swing high
      if(high[i] > high[i-1] && high[i] > high[i+1])
      {
         double swing_high = high[i];
         if(swing_high > current_price)
            liquidity_above += (swing_high - current_price);
         else
            liquidity_below += (current_price - swing_high);
      }

      // Swing low
      if(low[i] < low[i-1] && low[i] < low[i+1])
      {
         double swing_low = low[i];
         if(swing_low < current_price)
            liquidity_below += (current_price - swing_low);
         else
            liquidity_above += (swing_low - current_price);
      }
   }

   double total_liquidity = liquidity_above + liquidity_below;
   if(total_liquidity == 0.0) return 0.0;

   // Positive N = more liquidity below (bullish)
   // Negative N = more liquidity above (bearish)
   double N = (liquidity_below - liquidity_above) / total_liquidity;

   return MathMax(-1.0, MathMin(1.0, N));
}

//+------------------------------------------------------------------+
//| Calculate A-Axis (Alignment - Recent Sweep Direction)            |
//| A = based on ATR sweeps of highs/lows                            |
//+------------------------------------------------------------------+
double CFPFStateEngine::CalculateA()
{
   if(!m_Initialized) return 0.0;

   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);

   if(CopyBuffer(m_ATR_Handle, 0, 0, 1, atr_buffer) < 1)
      return 0.0;

   double atr = atr_buffer[0];
   double threshold = atr * m_TrapThreshold;

   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int copied = CopyHigh(m_symbol, m_timeframe, 0, 10, high);
   if(copied < 10) return 0.0;

   CopyLow(m_symbol, m_timeframe, 0, 10, low);

   // Find recent high/low sweeps
   double recent_high = high[0];
   double recent_low = low[0];

   for(int i = 1; i < 10; i++)
   {
      recent_high = MathMax(recent_high, high[i]);
      recent_low = MathMin(recent_low, low[i]);
   }

   double current_price = iClose(m_symbol, m_timeframe, 0);

   // Check for upward sweep (bearish alignment)
   bool upward_sweep = (recent_high - current_price) > threshold;

   // Check for downward sweep (bullish alignment)
   bool downward_sweep = (current_price - recent_low) > threshold;

   double A = 0.0;

   if(downward_sweep && !upward_sweep)
      A = 0.5;  // Bullish alignment
   else if(upward_sweep && !downward_sweep)
      A = -0.5; // Bearish alignment
   else if(downward_sweep && upward_sweep)
   {
      // Both sweeps - use relative strength
      double down_strength = (current_price - recent_low) / atr;
      double up_strength = (recent_high - current_price) / atr;
      A = (down_strength - up_strength) / (down_strength + up_strength);
   }

   return MathMax(-1.0, MathMin(1.0, A));
}

//+------------------------------------------------------------------+
//| Calculate C-Axis (Coherence - Trap Detection)                    |
//| C = bull trap vs bear trap detection                             |
//+------------------------------------------------------------------+
double CFPFStateEngine::CalculateC()
{
   if(!m_Initialized) return 0.0;

   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int copied = CopyOpen(m_symbol, m_timeframe, 0, 5, open);
   if(copied < 5) return 0.0;

   CopyHigh(m_symbol, m_timeframe, 0, 5, high);
   CopyLow(m_symbol, m_timeframe, 0, 5, low);
   CopyClose(m_symbol, m_timeframe, 0, 5, close);

   int bull_traps = 0;
   int bear_traps = 0;

   for(int i = 1; i < 5; i++)
   {
      double midpoint = (high[i] + low[i]) / 2.0;
      double upper_wick = high[i] - MathMax(open[i], close[i]);
      double lower_wick = MathMin(open[i], close[i]) - low[i];
      double body = MathAbs(close[i] - open[i]);

      // Bull trap: wick above recent high, close below midpoint
      if(upper_wick > body * 1.5 && close[i] < midpoint)
         bull_traps++;

      // Bear trap: wick below recent low, close above midpoint
      if(lower_wick > body * 1.5 && close[i] > midpoint)
         bear_traps++;
   }

   double C = 0.0;

   if(bear_traps > bull_traps)
      C = 0.4;  // Bullish (bear traps suggest reversal up)
   else if(bull_traps > bear_traps)
      C = -0.4; // Bearish (bull traps suggest reversal down)

   return MathMax(-1.0, MathMin(1.0, C));
}

//+------------------------------------------------------------------+
//| Calculate all FPF axes and apply smoothing                       |
//+------------------------------------------------------------------+
void CFPFStateEngine::CalculateState()
{
   if(!m_Initialized) return;

   // Save previous state
   ArrayCopy(m_FPF_StatePrev, m_FPF_State);

   // Calculate raw values
   m_FPF_StateRaw[0] = CalculateP();
   m_FPF_StateRaw[1] = CalculateE();
   m_FPF_StateRaw[2] = CalculateN();
   m_FPF_StateRaw[3] = CalculateA();
   m_FPF_StateRaw[4] = CalculateC();

   // Apply EMA smoothing
   ApplySmoothing();

   // Detect regime
   DetectRegimeInternal();
}

//+------------------------------------------------------------------+
//| Apply exponential moving average smoothing                       |
//+------------------------------------------------------------------+
void CFPFStateEngine::ApplySmoothing()
{
   for(int i = 0; i < 5; i++)
   {
      // EMA: State_new = mu * Raw + (1 - mu) * State_old
      m_FPF_State[i] = m_mu * m_FPF_StateRaw[i] + (1.0 - m_mu) * m_FPF_State[i];
   }
}

//+------------------------------------------------------------------+
//| Update rotation metrics (SpotX, SpotY, velocity, angle, etc.)    |
//+------------------------------------------------------------------+
void CFPFStateEngine::UpdateRotationMetrics()
{
   // Store previous spot
   m_PrevSpotX = m_SpotX;
   m_PrevSpotY = m_SpotY;

   // Project to 2D using P and E axes
   m_SpotX = m_FPF_State[0];  // P (Perception)
   m_SpotY = m_FPF_State[1];  // E (Emotion)

   // Calculate rotation velocity (Euclidean distance)
   double dx = m_SpotX - m_PrevSpotX;
   double dy = m_SpotY - m_PrevSpotY;
   m_RotationVelocity = MathSqrt(dx * dx + dy * dy);

   // Calculate rotation angle
   if(m_RotationVelocity > 0.001)
   {
      m_RotationAngle = MathArctan2(dy, dx) * 180.0 / M_PI;
   }

   // Orbital energy: mean absolute difference across adjacent axes
   double sum_diff = 0.0;
   for(int i = 0; i < 4; i++)
   {
      sum_diff += MathAbs(m_FPF_State[i+1] - m_FPF_State[i]);
   }
   m_OrbitalEnergy = sum_diff / 4.0;

   // Resonance energy: RMS magnitude of all components
   double sum_sq = 0.0;
   for(int i = 0; i < 5; i++)
   {
      sum_sq += m_FPF_State[i] * m_FPF_State[i];
   }
   m_ResonanceEnergy = MathSqrt(sum_sq / 5.0);
}

//+------------------------------------------------------------------+
//| Detect market regime based on FPF state                          |
//+------------------------------------------------------------------+
void CFPFStateEngine::DetectRegimeInternal()
{
   double P = m_FPF_State[0];
   double E = m_FPF_State[1];
   double N = m_FPF_State[2];
   double A = m_FPF_State[3];

   // REGIME_TREND_UP: P > 0.3 AND E > 0.1
   if(P > 0.3 && E > 0.1)
   {
      m_CurrentRegime = REGIME_TREND_UP;
      return;
   }

   // REGIME_TREND_DOWN: P < -0.3 AND E < -0.1
   if(P < -0.3 && E < -0.1)
   {
      m_CurrentRegime = REGIME_TREND_DOWN;
      return;
   }

   // REGIME_REVERSAL_UP: P < -0.1 AND N > 0 AND A > 0
   if(P < -0.1 && N > 0 && A > 0)
   {
      m_CurrentRegime = REGIME_REVERSAL_UP;
      return;
   }

   // REGIME_REVERSAL_DOWN: P > 0.1 AND N < 0 AND A < 0
   if(P > 0.1 && N < 0 && A < 0)
   {
      m_CurrentRegime = REGIME_REVERSAL_DOWN;
      return;
   }

   // REGIME_CHOP: |P| < 0.15 AND |E| < 0.15
   if(MathAbs(P) < 0.15 && MathAbs(E) < 0.15)
   {
      m_CurrentRegime = REGIME_CHOP;
      return;
   }

   // Default: REGIME_NONE
   m_CurrentRegime = REGIME_NONE;
}

//+------------------------------------------------------------------+
//| Public regime detection (returns current regime)                 |
//+------------------------------------------------------------------+
MarketRegime CFPFStateEngine::DetectRegime()
{
   return m_CurrentRegime;
}

//+------------------------------------------------------------------+
//| Get regime as string                                             |
//+------------------------------------------------------------------+
string CFPFStateEngine::GetRegimeString()
{
   switch(m_CurrentRegime)
   {
      case REGIME_TREND_UP:       return "TREND_UP";
      case REGIME_TREND_DOWN:     return "TREND_DOWN";
      case REGIME_REVERSAL_UP:    return "REVERSAL_UP";
      case REGIME_REVERSAL_DOWN:  return "REVERSAL_DOWN";
      case REGIME_CHOP:           return "CHOP";
      default:                    return "NONE";
   }
}
//+------------------------------------------------------------------+
