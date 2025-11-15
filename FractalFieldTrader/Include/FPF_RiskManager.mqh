//+------------------------------------------------------------------+
//| FPF_RiskManager.mqh                                               |
//| Adaptive Risk Management with FPF State Integration              |
//| Dynamically adjusts position sizing, stops, and targets          |
//+------------------------------------------------------------------+
#property copyright "FPF Adaptive Risk Manager v1.0"
#property strict

#include "FPF_StateEngine.mqh"

//+------------------------------------------------------------------+
//| Risk Configuration Structure                                      |
//+------------------------------------------------------------------+
struct SRiskConfig
{
   // Base risk settings
   double BaseRiskPercent;           // Starting risk per trade (e.g., 0.5%)
   double MinRiskPercent;            // Minimum allowed risk (e.g., 0.1%)
   double MaxRiskPercent;            // Maximum allowed risk (e.g., 2.0%)

   // Confidence scaling
   bool UseConfidenceScaling;        // Enable FPF confidence-based scaling
   double ConfidenceMultiplier;      // Max multiplier for high confidence (e.g., 2.0)
   double MinConfidenceThreshold;    // Below this, use min risk (e.g., 0.4)

   // Regime scaling
   bool UseRegimeScaling;            // Enable regime-based risk adjustment
   double TrendRegimeMultiplier;     // Multiplier for TREND regimes (e.g., 1.5)
   double ReversalRegimeMultiplier;  // Multiplier for REVERSAL regimes (e.g., 1.0)
   double ChopRegimeMultiplier;      // Multiplier for CHOP (e.g., 0.3)

   // Dynamic stops
   bool UseAdaptiveStops;            // Enable adaptive stop loss
   double BaseStopATRMultiplier;     // Base ATR multiplier (e.g., 2.0)
   double TrendStopMultiplier;       // Trend stop multiplier (e.g., 2.5)
   double ChopStopMultiplier;        // Chop stop multiplier (e.g., 1.5)

   // Dynamic targets
   bool UseAdaptiveTargets;          // Enable adaptive take profit
   double BaseTargetRMultiple;       // Base R-multiple (e.g., 3.0)
   double TrendTargetRMultiple;      // Trend target (e.g., 4.0)
   double ReversalTargetRMultiple;   // Reversal target (e.g., 2.5)

   // Heat management
   bool UseHeatManagement;           // Track total portfolio heat
   double MaxPortfolioHeat;          // Max % of account at risk (e.g., 6%)

   // Drawdown protection
   bool UseDrawdownScaling;          // Scale down risk in drawdown
   double DrawdownScaleStart;        // Start scaling at DD% (e.g., 5%)
   double DrawdownScaleMax;          // Max DD before full stop (e.g., 15%)
};

//+------------------------------------------------------------------+
//| Risk Calculation Result                                           |
//+------------------------------------------------------------------+
struct SRiskResult
{
   double RiskPercent;               // Final risk percent for this trade
   double PositionSize;              // Lot size
   double StopDistance;              // Stop loss distance in price
   double StopPrice;                 // Actual SL price
   double TargetDistance;            // Take profit distance
   double TargetPrice;               // Actual TP price
   double ExpectedR;                 // Expected R-multiple
   string RiskReason;                // Explanation of risk adjustment
};

//+------------------------------------------------------------------+
//| Performance Tracking for Kelly/Heat                               |
//+------------------------------------------------------------------+
struct SPerformanceTracker
{
   int ConsecutiveWins;
   int ConsecutiveLosses;
   double CurrentDrawdown;
   double PeakBalance;
   double TotalRiskExposed;          // Current open risk
   datetime LastTradeTime;
};

//+------------------------------------------------------------------+
//| Adaptive Risk Manager Class                                       |
//+------------------------------------------------------------------+
class CFPFRiskManager
{
private:
   SRiskConfig m_Config;
   SPerformanceTracker m_Performance;

   // Account tracking
   double m_StartingBalance;
   double m_CurrentBalance;

   // Initialization flag
   bool m_Initialized;

   // Internal calculation methods
   double CalculateConfidenceMultiplier(double P, double E, double N, double resonance);
   double CalculateRegimeMultiplier(MarketRegime regime);
   double CalculateDrawdownScalar();
   double GetCurrentDrawdownPercent();

public:
   CFPFRiskManager();
   ~CFPFRiskManager();

   // Initialization
   void Init(SRiskConfig &config);
   void UpdateBalance(double balance);

   // Main risk calculation
   SRiskResult CalculateRisk(string symbol, ENUM_TIMEFRAMES tf, int direction,
                             double entry_price, CFPFStateEngine* fpf_engine);

   // Heat management
   void AddOpenRisk(double risk_amount);
   void RemoveOpenRisk(double risk_amount);
   bool IsHeatAvailable();

   // Performance tracking
   void RecordWin();
   void RecordLoss();
   void UpdateDrawdown();

   // Getters
   double GetCurrentRiskPercent();
   double GetCurrentDrawdown() { return m_Performance.CurrentDrawdown; }
   double GetTotalHeat() { return m_Performance.TotalRiskExposed; }

   // Status
   bool IsInitialized() { return m_Initialized; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CFPFRiskManager::CFPFRiskManager()
{
   m_Initialized = false;
   m_StartingBalance = 0;
   m_CurrentBalance = 0;

   m_Performance.ConsecutiveWins = 0;
   m_Performance.ConsecutiveLosses = 0;
   m_Performance.CurrentDrawdown = 0;
   m_Performance.PeakBalance = 0;
   m_Performance.TotalRiskExposed = 0;
   m_Performance.LastTradeTime = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CFPFRiskManager::~CFPFRiskManager()
{
}

//+------------------------------------------------------------------+
//| Initialize risk manager                                           |
//+------------------------------------------------------------------+
void CFPFRiskManager::Init(SRiskConfig &config)
{
   m_Config = config;
   m_StartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_CurrentBalance = m_StartingBalance;
   m_Performance.PeakBalance = m_StartingBalance;
   m_Initialized = true;
}

//+------------------------------------------------------------------+
//| Update current balance                                            |
//+------------------------------------------------------------------+
void CFPFRiskManager::UpdateBalance(double balance)
{
   m_CurrentBalance = balance;

   // Update peak for drawdown calculation
   if(balance > m_Performance.PeakBalance)
      m_Performance.PeakBalance = balance;
}

//+------------------------------------------------------------------+
//| Calculate confidence-based multiplier from FPF state             |
//+------------------------------------------------------------------+
double CFPFRiskManager::CalculateConfidenceMultiplier(double P, double E, double N, double resonance)
{
   if(!m_Config.UseConfidenceScaling)
      return 1.0;

   // Build composite confidence score from FPF axes
   // Higher absolute values = stronger signal
   double p_strength = MathAbs(P);
   double e_strength = MathAbs(E);
   double n_strength = MathAbs(N);

   // Weighted average (P and E are primary trend indicators)
   double composite_confidence = (p_strength * 0.4) + (e_strength * 0.3) +
                                 (n_strength * 0.2) + (resonance * 0.1);

   // Normalize to 0-1 range (FPF values are -1 to 1, so max composite ≈ 1.0)
   composite_confidence = MathMax(0, MathMin(1.0, composite_confidence));

   // If below minimum threshold, return reduced multiplier
   if(composite_confidence < m_Config.MinConfidenceThreshold)
      return 0.5;  // Half risk for low confidence

   // Scale linearly from 1.0 to ConfidenceMultiplier
   // 0.4 confidence → 1.0x
   // 1.0 confidence → ConfidenceMultiplier (e.g., 2.0x)
   double normalized = (composite_confidence - m_Config.MinConfidenceThreshold) /
                       (1.0 - m_Config.MinConfidenceThreshold);

   double multiplier = 1.0 + (normalized * (m_Config.ConfidenceMultiplier - 1.0));

   return MathMax(0.5, MathMin(m_Config.ConfidenceMultiplier, multiplier));
}

//+------------------------------------------------------------------+
//| Calculate regime-based risk multiplier                           |
//+------------------------------------------------------------------+
double CFPFRiskManager::CalculateRegimeMultiplier(MarketRegime regime)
{
   if(!m_Config.UseRegimeScaling)
      return 1.0;

   switch(regime)
   {
      case REGIME_TREND_UP:
      case REGIME_TREND_DOWN:
         return m_Config.TrendRegimeMultiplier;  // e.g., 1.5x in trends

      case REGIME_REVERSAL_UP:
      case REGIME_REVERSAL_DOWN:
         return m_Config.ReversalRegimeMultiplier;  // e.g., 1.0x in reversals

      case REGIME_CHOP:
         return m_Config.ChopRegimeMultiplier;  // e.g., 0.3x in chop

      default:
         return 0.7;  // Conservative for REGIME_NONE
   }
}

//+------------------------------------------------------------------+
//| Calculate drawdown-based risk scalar                             |
//+------------------------------------------------------------------+
double CFPFRiskManager::CalculateDrawdownScalar()
{
   if(!m_Config.UseDrawdownScaling)
      return 1.0;

   double dd_percent = GetCurrentDrawdownPercent();

   // No drawdown → full risk
   if(dd_percent <= m_Config.DrawdownScaleStart)
      return 1.0;

   // Beyond max drawdown → zero risk
   if(dd_percent >= m_Config.DrawdownScaleMax)
      return 0.0;

   // Linear scaling between start and max
   // e.g., 5% DD → 1.0, 10% DD → 0.5, 15% DD → 0.0
   double range = m_Config.DrawdownScaleMax - m_Config.DrawdownScaleStart;
   double distance = dd_percent - m_Config.DrawdownScaleStart;

   double scalar = 1.0 - (distance / range);

   return MathMax(0.0, MathMin(1.0, scalar));
}

//+------------------------------------------------------------------+
//| Get current drawdown percentage                                  |
//+------------------------------------------------------------------+
double CFPFRiskManager::GetCurrentDrawdownPercent()
{
   if(m_Performance.PeakBalance == 0)
      return 0;

   double dd = (m_Performance.PeakBalance - m_CurrentBalance) / m_Performance.PeakBalance * 100.0;
   return MathMax(0, dd);
}

//+------------------------------------------------------------------+
//| Main risk calculation method                                     |
//+------------------------------------------------------------------+
SRiskResult CFPFRiskManager::CalculateRisk(string symbol, ENUM_TIMEFRAMES tf,
                                           int direction, double entry_price,
                                           CFPFStateEngine* fpf_engine)
{
   SRiskResult result;
   ZeroMemory(result);

   if(!m_Initialized || fpf_engine == NULL)
   {
      // Fallback to base risk
      result.RiskPercent = m_Config.BaseRiskPercent;
      result.RiskReason = "FALLBACK_BASE_RISK";
      return result;
   }

   // Get FPF state
   double P = fpf_engine.GetP();
   double E = fpf_engine.GetE();
   double N = fpf_engine.GetN();
   double resonance = fpf_engine.GetResonanceEnergy();
   MarketRegime regime = fpf_engine.GetRegime();

   // Start with base risk
   double risk_percent = m_Config.BaseRiskPercent;
   string reason = "BASE";

   // Apply confidence multiplier
   double conf_mult = CalculateConfidenceMultiplier(P, E, N, resonance);
   risk_percent *= conf_mult;
   reason += StringFormat("_CONF:%.2f", conf_mult);

   // Apply regime multiplier
   double regime_mult = CalculateRegimeMultiplier(regime);
   risk_percent *= regime_mult;
   reason += StringFormat("_REGIME:%.2f", regime_mult);

   // Apply drawdown scalar
   double dd_scalar = CalculateDrawdownScalar();
   risk_percent *= dd_scalar;
   if(dd_scalar < 1.0)
      reason += StringFormat("_DD:%.2f", dd_scalar);

   // Clamp to min/max
   risk_percent = MathMax(m_Config.MinRiskPercent, MathMin(m_Config.MaxRiskPercent, risk_percent));

   result.RiskPercent = risk_percent;
   result.RiskReason = reason;

   // Calculate stop distance
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   int atr_handle = iATR(symbol, tf, 14);

   double stop_mult = m_Config.BaseStopATRMultiplier;

   if(m_Config.UseAdaptiveStops)
   {
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN)
         stop_mult = m_Config.TrendStopMultiplier;  // Wider stops in trends
      else if(regime == REGIME_CHOP)
         stop_mult = m_Config.ChopStopMultiplier;   // Tighter stops in chop
   }

   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
   {
      result.StopDistance = atr_buffer[0] * stop_mult;

      // Calculate stop price
      if(direction == 1)  // LONG
      {
         result.StopPrice = entry_price - result.StopDistance;
      }
      else  // SHORT
      {
         result.StopPrice = entry_price + result.StopDistance;
      }
   }
   else
   {
      result.StopDistance = 0;
      result.StopPrice = 0;
   }

   IndicatorRelease(atr_handle);

   // Calculate target distance
   double target_r = m_Config.BaseTargetRMultiple;

   if(m_Config.UseAdaptiveTargets)
   {
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN)
         target_r = m_Config.TrendTargetRMultiple;  // Larger targets in trends
      else if(regime == REGIME_REVERSAL_UP || regime == REGIME_REVERSAL_DOWN)
         target_r = m_Config.ReversalTargetRMultiple;  // Moderate targets in reversals
   }

   result.ExpectedR = target_r;
   result.TargetDistance = result.StopDistance * target_r;

   // Calculate target price
   if(direction == 1)  // LONG
   {
      result.TargetPrice = entry_price + result.TargetDistance;
   }
   else  // SHORT
   {
      result.TargetPrice = entry_price - result.TargetDistance;
   }

   // Calculate position size
   if(result.StopDistance > 0)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_money = balance * (result.RiskPercent / 100.0);

      double tick_val = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_size > 0 && tick_val > 0)
      {
         double lots = risk_money / (result.StopDistance / tick_size * tick_val);

         double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

         lots = MathFloor(lots / step) * step;
         lots = MathMax(min_lot, MathMin(max_lot, lots));

         result.PositionSize = lots;
      }
   }

   return result;
}

//+------------------------------------------------------------------+
//| Add open risk to heat tracker                                    |
//+------------------------------------------------------------------+
void CFPFRiskManager::AddOpenRisk(double risk_amount)
{
   m_Performance.TotalRiskExposed += risk_amount;
}

//+------------------------------------------------------------------+
//| Remove closed risk from heat tracker                             |
//+------------------------------------------------------------------+
void CFPFRiskManager::RemoveOpenRisk(double risk_amount)
{
   m_Performance.TotalRiskExposed -= risk_amount;
   m_Performance.TotalRiskExposed = MathMax(0, m_Performance.TotalRiskExposed);
}

//+------------------------------------------------------------------+
//| Check if portfolio heat allows new trade                         |
//+------------------------------------------------------------------+
bool CFPFRiskManager::IsHeatAvailable()
{
   if(!m_Config.UseHeatManagement)
      return true;

   double current_heat_pct = (m_Performance.TotalRiskExposed / m_CurrentBalance) * 100.0;

   return current_heat_pct < m_Config.MaxPortfolioHeat;
}

//+------------------------------------------------------------------+
//| Record winning trade                                             |
//+------------------------------------------------------------------+
void CFPFRiskManager::RecordWin()
{
   m_Performance.ConsecutiveWins++;
   m_Performance.ConsecutiveLosses = 0;
   m_Performance.LastTradeTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Record losing trade                                              |
//+------------------------------------------------------------------+
void CFPFRiskManager::RecordLoss()
{
   m_Performance.ConsecutiveLosses++;
   m_Performance.ConsecutiveWins = 0;
   m_Performance.LastTradeTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Update drawdown tracking                                         |
//+------------------------------------------------------------------+
void CFPFRiskManager::UpdateDrawdown()
{
   UpdateBalance(AccountInfoDouble(ACCOUNT_BALANCE));
   m_Performance.CurrentDrawdown = GetCurrentDrawdownPercent();
}

//+------------------------------------------------------------------+
//| Get current effective risk percent                               |
//+------------------------------------------------------------------+
double CFPFRiskManager::GetCurrentRiskPercent()
{
   double base = m_Config.BaseRiskPercent;

   // Apply drawdown scaling
   if(m_Config.UseDrawdownScaling)
   {
      base *= CalculateDrawdownScalar();
   }

   return base;
}
//+------------------------------------------------------------------+
