//+------------------------------------------------------------------+
//| FPF_TradeLog.mqh                                                  |
//| Trade context logging with FPF state and regime                   |
//| Logs each trade with entry conditions for offline analysis        |
//+------------------------------------------------------------------+
#property copyright "FPF Trade Logger v1.0"
#property strict

#include "FPF_StateEngine.mqh"

//+------------------------------------------------------------------+
//| Trade Context Structure                                           |
//| Stores FPF state at trade entry for later logging                |
//+------------------------------------------------------------------+
struct STradeContext
{
   ulong ticket;
   datetime open_time;
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   int direction;        // 1 = long, -1 = short
   double volume;
   double entry_price;
   double sl;
   double tp;

   // FPF state at entry
   double P;
   double E;
   double N;
   double A;
   double C;
   string regime;

   // Rotation metrics at entry
   double spot_x;
   double spot_y;
   double rot_velocity;
   double rot_angle;
   double orbital_energy;
   double resonance_energy;
};

//+------------------------------------------------------------------+
//| Trade Logger Class                                                |
//+------------------------------------------------------------------+
class CFPFTradeLogger
{
private:
   int m_FileHandle;
   bool m_Enabled;
   string m_FilePath;

   // Store trade contexts (keyed by ticket in simple array)
   STradeContext m_TradeContexts[];
   int m_ContextCount;

   // Find context by ticket
   int FindContextIndex(ulong ticket);

public:
   CFPFTradeLogger();
   ~CFPFTradeLogger();

   // Initialization
   bool Init(string filePath);
   void Close();

   // Enable/disable logging
   void SetEnabled(bool enabled) { m_Enabled = enabled; }
   bool IsEnabled() { return m_Enabled; }

   // Store trade entry context
   void CacheEntryContext(ulong ticket, datetime open_time, string symbol,
                          ENUM_TIMEFRAMES tf, int direction, double volume,
                          double entry_price, double sl, double tp,
                          CFPFStateEngine* fpf_engine);

   // Record completed trade
   void RecordTrade(ulong ticket, datetime close_time, double exit_price, double profit);

   // Write header
   void WriteHeader();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CFPFTradeLogger::CFPFTradeLogger()
{
   m_FileHandle = INVALID_HANDLE;
   m_Enabled = false;
   m_FilePath = "";
   m_ContextCount = 0;
   ArrayResize(m_TradeContexts, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CFPFTradeLogger::~CFPFTradeLogger()
{
   Close();
}

//+------------------------------------------------------------------+
//| Initialize trade logger                                           |
//+------------------------------------------------------------------+
bool CFPFTradeLogger::Init(string filePath)
{
   m_FilePath = filePath;

   // Open file in write mode (create new or truncate existing)
   m_FileHandle = FileOpen(m_FilePath, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');

   if(m_FileHandle == INVALID_HANDLE)
   {
      Print("FPF_TradeLog ERROR: Cannot create log file: ", m_FilePath);
      Print("Error code: ", GetLastError());
      m_Enabled = false;
      return false;
   }

   // Write CSV header
   WriteHeader();

   FileClose(m_FileHandle);
   m_FileHandle = INVALID_HANDLE;

   m_Enabled = true;
   Print("FPF_TradeLog: Initialized successfully -> ", m_FilePath);

   return true;
}

//+------------------------------------------------------------------+
//| Close logger and release resources                               |
//+------------------------------------------------------------------+
void CFPFTradeLogger::Close()
{
   if(m_FileHandle != INVALID_HANDLE)
   {
      FileClose(m_FileHandle);
      m_FileHandle = INVALID_HANDLE;
   }

   m_Enabled = false;
}

//+------------------------------------------------------------------+
//| Write CSV header                                                  |
//+------------------------------------------------------------------+
void CFPFTradeLogger::WriteHeader()
{
   if(m_FileHandle == INVALID_HANDLE) return;

   FileWrite(m_FileHandle,
             "Ticket", "OpenTime", "CloseTime", "Symbol", "Timeframe",
             "Direction", "Volume", "EntryPrice", "ExitPrice", "SL", "TP",
             "Profit", "ProfitR",
             "P", "E", "N", "A", "C", "Regime",
             "SpotX", "SpotY", "RotVel", "RotAngle",
             "OrbitalEnergy", "ResonanceEnergy");
}

//+------------------------------------------------------------------+
//| Cache trade entry context (called when trade is opened)          |
//+------------------------------------------------------------------+
void CFPFTradeLogger::CacheEntryContext(ulong ticket, datetime open_time,
                                         string symbol, ENUM_TIMEFRAMES tf,
                                         int direction, double volume,
                                         double entry_price, double sl, double tp,
                                         CFPFStateEngine* fpf_engine)
{
   if(!m_Enabled) return;
   if(fpf_engine == NULL) return;

   // Create new context
   STradeContext ctx;
   ctx.ticket = ticket;
   ctx.open_time = open_time;
   ctx.symbol = symbol;
   ctx.timeframe = tf;
   ctx.direction = direction;
   ctx.volume = volume;
   ctx.entry_price = entry_price;
   ctx.sl = sl;
   ctx.tp = tp;

   // Capture FPF state
   ctx.P = fpf_engine.GetP();
   ctx.E = fpf_engine.GetE();
   ctx.N = fpf_engine.GetN();
   ctx.A = fpf_engine.GetA();
   ctx.C = fpf_engine.GetC();
   ctx.regime = fpf_engine.GetRegimeString();

   // Capture rotation metrics
   ctx.spot_x = fpf_engine.GetSpotX();
   ctx.spot_y = fpf_engine.GetSpotY();
   ctx.rot_velocity = fpf_engine.GetRotationVelocity();
   ctx.rot_angle = fpf_engine.GetRotationAngle();
   ctx.orbital_energy = fpf_engine.GetOrbitalEnergy();
   ctx.resonance_energy = fpf_engine.GetResonanceEnergy();

   // Add to context array
   int idx = m_ContextCount;
   m_ContextCount++;
   ArrayResize(m_TradeContexts, m_ContextCount);
   m_TradeContexts[idx] = ctx;
}

//+------------------------------------------------------------------+
//| Find context index by ticket                                     |
//+------------------------------------------------------------------+
int CFPFTradeLogger::FindContextIndex(ulong ticket)
{
   for(int i = 0; i < m_ContextCount; i++)
   {
      if(m_TradeContexts[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Record completed trade (called when trade is closed)             |
//+------------------------------------------------------------------+
void CFPFTradeLogger::RecordTrade(ulong ticket, datetime close_time,
                                   double exit_price, double profit)
{
   if(!m_Enabled) return;

   // Find cached context
   int ctx_idx = FindContextIndex(ticket);
   if(ctx_idx < 0)
   {
      Print("FPF_TradeLog WARNING: No cached context for ticket #", ticket);
      return;
   }

   STradeContext ctx = m_TradeContexts[ctx_idx];

   // Calculate R multiple (profit relative to risk)
   double risk_distance = MathAbs(ctx.entry_price - ctx.sl);
   double profit_r = 0.0;

   if(risk_distance > 0)
   {
      // Get tick value to convert price distance to monetary value
      double tick_val = SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_size > 0 && tick_val > 0)
      {
         double risk_money = (risk_distance / tick_size) * tick_val * ctx.volume;
         if(risk_money > 0)
            profit_r = profit / risk_money;
      }
   }

   // Open file in append mode
   m_FileHandle = FileOpen(m_FilePath, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');

   if(m_FileHandle == INVALID_HANDLE)
   {
      Print("FPF_TradeLog ERROR: Cannot open log file for writing");
      return;
   }

   // Seek to end
   FileSeek(m_FileHandle, 0, SEEK_END);

   // Write trade row
   FileWrite(m_FileHandle,
             (string)ctx.ticket,
             TimeToString(ctx.open_time, TIME_DATE|TIME_MINUTES),
             TimeToString(close_time, TIME_DATE|TIME_MINUTES),
             ctx.symbol,
             EnumToString(ctx.timeframe),
             ctx.direction == 1 ? "LONG" : "SHORT",
             DoubleToString(ctx.volume, 2),
             DoubleToString(ctx.entry_price, 5),
             DoubleToString(exit_price, 5),
             DoubleToString(ctx.sl, 5),
             DoubleToString(ctx.tp, 5),
             DoubleToString(profit, 2),
             DoubleToString(profit_r, 2),
             DoubleToString(ctx.P, 4),
             DoubleToString(ctx.E, 4),
             DoubleToString(ctx.N, 4),
             DoubleToString(ctx.A, 4),
             DoubleToString(ctx.C, 4),
             ctx.regime,
             DoubleToString(ctx.spot_x, 4),
             DoubleToString(ctx.spot_y, 4),
             DoubleToString(ctx.rot_velocity, 4),
             DoubleToString(ctx.rot_angle, 2),
             DoubleToString(ctx.orbital_energy, 4),
             DoubleToString(ctx.resonance_energy, 4));

   FileClose(m_FileHandle);
   m_FileHandle = INVALID_HANDLE;

   // Remove from context array (simple approach: just mark as processed)
   // In a more complex system, we could compact the array
   // For now, keeping it simple
}
//+------------------------------------------------------------------+
