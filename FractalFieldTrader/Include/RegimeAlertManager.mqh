//+------------------------------------------------------------------+
//| RegimeAlertManager.mqh                                           |
//| Intelligent alert system for regime transitions and field events|
//+------------------------------------------------------------------+

#include "AdaptiveChronoFilter.mqh"

enum ENUM_ALERT_LEVEL
{
    ALERT_INFO,       // Informational (regime change)
    ALERT_WARNING,    // Warning (entering risky regime)
    ALERT_CRITICAL    // Critical (market structure breaking)
};

enum ENUM_ALERT_TYPE
{
    ALERT_JOURNAL,    // Log to MT5 Journal
    ALERT_FILE,       // Write to alerts.txt file
    ALERT_POPUP,      // Show popup dialog
    ALERT_SOUND,      // Play alert sound
    ALERT_EMAIL,      // Send email (if configured)
    ALERT_MOBILE      // Push to mobile (if configured)
};

struct SAlertConfig
{
    bool EnableJournal;
    bool EnableFile;
    bool EnablePopup;
    bool EnableSound;
    bool EnableEmail;
    bool EnableMobile;

    int MinimumSpacingSeconds;  // Minimum time between identical alerts
    bool OnlyAlertTradingHours;
    bool AlertOnRegimeChange;
    bool AlertOnHighCoherence;
    bool AlertOnLowCoherence;
    bool AlertOnChaosEntry;
    bool AlertOnFlowEntry;
};

struct SAlertHistory
{
    string message;
    datetime time;
    ENUM_ALERT_LEVEL level;
};

class CRegimeAlertManager
{
private:
    SAlertConfig m_config;
    SAlertHistory m_history[];
    int m_history_size;

    string m_last_regime;
    datetime m_last_alert_time;
    double m_last_coherence;
    string m_last_attractor;

    string m_alert_file_path;

    // Alert sounds (built-in MT5 sounds)
    string m_info_sound;
    string m_warning_sound;
    string m_critical_sound;

public:
    CRegimeAlertManager()
    {
        // Default configuration
        m_config.EnableJournal = true;
        m_config.EnableFile = true;
        m_config.EnablePopup = false;  // Can be annoying
        m_config.EnableSound = true;
        m_config.EnableEmail = false;
        m_config.EnableMobile = false;

        m_config.MinimumSpacingSeconds = 300;  // 5 minutes between identical alerts
        m_config.OnlyAlertTradingHours = false;
        m_config.AlertOnRegimeChange = true;
        m_config.AlertOnHighCoherence = true;
        m_config.AlertOnLowCoherence = true;
        m_config.AlertOnChaosEntry = true;
        m_config.AlertOnFlowEntry = true;

        m_history_size = 100;
        ArrayResize(m_history, m_history_size);

        m_last_regime = "INITIALIZING";
        m_last_alert_time = 0;
        m_last_coherence = 50.0;
        m_last_attractor = "UNKNOWN";

        m_alert_file_path = "FractalFieldAlerts.txt";

        // MT5 built-in sounds
        m_info_sound = "alert2.wav";
        m_warning_sound = "alert.wav";
        m_critical_sound = "timeout.wav";

        Print("✅ Regime Alert Manager initialized");
    }

    //+------------------------------------------------------------------+
    //| Configure alert settings                                         |
    //+------------------------------------------------------------------+
    void Configure(bool journal, bool file, bool popup, bool sound)
    {
        m_config.EnableJournal = journal;
        m_config.EnableFile = file;
        m_config.EnablePopup = popup;
        m_config.EnableSound = sound;
    }

    void SetMinimumSpacing(int seconds)
    {
        m_config.MinimumSpacingSeconds = seconds;
    }

    void SetAlertConditions(bool regime_change, bool high_coh, bool low_coh, bool chaos, bool flow)
    {
        m_config.AlertOnRegimeChange = regime_change;
        m_config.AlertOnHighCoherence = high_coh;
        m_config.AlertOnLowCoherence = low_coh;
        m_config.AlertOnChaosEntry = chaos;
        m_config.AlertOnFlowEntry = flow;
    }

    //+------------------------------------------------------------------+
    //| Monitor field state and trigger alerts                          |
    //+------------------------------------------------------------------+
    void Monitor(CAdaptiveChronoFilter* adaptive_filter, CCoherenceMeasure* field)
    {
        if(CheckPointer(adaptive_filter) == POINTER_INVALID || CheckPointer(field) == POINTER_INVALID)
            return;

        string current_regime = adaptive_filter.GetCurrentRegime();
        double current_coherence = field.GetOverallCoherence();
        string current_attractor = field.GetCurrentAttractor();
        double regime_confidence = adaptive_filter.GetRegimeConfidence();

        // Check for regime transition
        if(m_config.AlertOnRegimeChange && current_regime != m_last_regime && m_last_regime != "INITIALIZING")
        {
            string message = StringFormat("REGIME SHIFT: %s → %s (%.1f%% confidence)",
                                         m_last_regime, current_regime, regime_confidence * 100);

            ENUM_ALERT_LEVEL level = ALERT_INFO;

            // Upgrade to WARNING if entering risky regime
            if(current_regime == "CHAOTIC_ACCELERATION" || current_regime == "VOLATILITY_STORM")
                level = ALERT_WARNING;

            // Upgrade to CRITICAL if coherence dropping fast
            if(current_coherence < 40 && m_last_coherence > 60)
                level = ALERT_CRITICAL;

            SendAlert(message, level);
        }

        // Check for chaos entry
        if(m_config.AlertOnChaosEntry && current_regime == "CHAOTIC_ACCELERATION" && m_last_regime != "CHAOTIC_ACCELERATION")
        {
            string message = StringFormat("⚠️ CHAOS DETECTED - Market entering chaotic acceleration (Coh: %.1f)", current_coherence);
            SendAlert(message, ALERT_WARNING);
        }

        // Check for flow state entry
        if(m_config.AlertOnFlowEntry && current_regime == "FLOW_STATE" && m_last_regime != "FLOW_STATE")
        {
            string message = StringFormat("✨ FLOW STATE - Optimal trading conditions (Coh: %.1f)", current_coherence);
            SendAlert(message, ALERT_INFO);
        }

        // Check for high coherence breakthrough
        if(m_config.AlertOnHighCoherence && current_coherence > 75 && m_last_coherence <= 75)
        {
            string message = StringFormat("🎯 HIGH COHERENCE - Field aligned at %.1f%% (Regime: %s)",
                                         current_coherence, current_regime);
            SendAlert(message, ALERT_INFO);
        }

        // Check for coherence collapse
        if(m_config.AlertOnLowCoherence && current_coherence < 40 && m_last_coherence >= 40)
        {
            string message = StringFormat("📉 LOW COHERENCE - Field degrading to %.1f%% (Regime: %s)",
                                         current_coherence, current_regime);
            SendAlert(message, ALERT_WARNING);
        }

        // Check for attractor transition
        if(current_attractor != m_last_attractor && m_last_attractor != "UNKNOWN" && m_last_attractor != "TRANSITIONING")
        {
            if(current_attractor == "HIGH_VOL_CHAOS")
            {
                string message = StringFormat("🌪️ ATTRACTOR SHIFT - Entering HIGH_VOL_CHAOS basin");
                SendAlert(message, ALERT_CRITICAL);
            }
            else if(current_attractor == "LOW_VOL_CYCLE")
            {
                string message = StringFormat("🎯 ATTRACTOR SHIFT - Entering LOW_VOL_CYCLE basin");
                SendAlert(message, ALERT_INFO);
            }
        }

        // Update state
        m_last_regime = current_regime;
        m_last_coherence = current_coherence;
        m_last_attractor = current_attractor;
    }

    //+------------------------------------------------------------------+
    //| Send alert through configured channels                          |
    //+------------------------------------------------------------------+
    void SendAlert(string message, ENUM_ALERT_LEVEL level)
    {
        // Check spacing
        datetime now = TimeCurrent();
        if(now - m_last_alert_time < m_config.MinimumSpacingSeconds)
            return;  // Too soon since last alert

        // Check trading hours if configured
        if(m_config.OnlyAlertTradingHours && !IsWithinTradingHours())
            return;

        // Store in history
        StoreAlert(message, now, level);

        // Format with timestamp and level
        string level_str = (level == ALERT_CRITICAL) ? "🚨 CRITICAL" :
                          (level == ALERT_WARNING) ? "⚠️ WARNING" : "ℹ️ INFO";

        string formatted = StringFormat("[%s] %s: %s",
                                       TimeToString(now, TIME_DATE|TIME_MINUTES),
                                       level_str, message);

        // Send through enabled channels
        if(m_config.EnableJournal)
        {
            Print("═══════════════════════════════════════════════════════════");
            Print(formatted);
            Print("═══════════════════════════════════════════════════════════");
        }

        if(m_config.EnableFile)
        {
            WriteToFile(formatted);
        }

        if(m_config.EnablePopup)
        {
            Alert(formatted);
        }

        if(m_config.EnableSound)
        {
            PlayAlertSound(level);
        }

        if(m_config.EnableEmail)
        {
            SendMail("Fractal Field Alert", formatted);
        }

        if(m_config.EnableMobile)
        {
            SendNotification(formatted);
        }

        m_last_alert_time = now;
    }

    //+------------------------------------------------------------------+
    //| Write alert to file                                             |
    //+------------------------------------------------------------------+
    void WriteToFile(string message)
    {
        int file = FileOpen(m_alert_file_path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
        if(file != INVALID_HANDLE)
        {
            FileSeek(file, 0, SEEK_END);
            FileWrite(file, message);
            FileClose(file);
        }
    }

    //+------------------------------------------------------------------+
    //| Play sound based on alert level                                 |
    //+------------------------------------------------------------------+
    void PlayAlertSound(ENUM_ALERT_LEVEL level)
    {
        string sound;

        switch(level)
        {
            case ALERT_INFO:
                sound = m_info_sound;
                break;
            case ALERT_WARNING:
                sound = m_warning_sound;
                break;
            case ALERT_CRITICAL:
                sound = m_critical_sound;
                break;
        }

        PlaySound(sound);
    }

    //+------------------------------------------------------------------+
    //| Store alert in history                                          |
    //+------------------------------------------------------------------+
    void StoreAlert(string message, datetime time, ENUM_ALERT_LEVEL level)
    {
        // Shift history
        for(int i = m_history_size - 1; i > 0; i--)
        {
            m_history[i] = m_history[i-1];
        }

        // Store new alert
        m_history[0].message = message;
        m_history[0].time = time;
        m_history[0].level = level;
    }

    //+------------------------------------------------------------------+
    //| Check if within trading hours (simplified)                      |
    //+------------------------------------------------------------------+
    bool IsWithinTradingHours()
    {
        MqlDateTime dt;
        TimeCurrent(dt);

        // Monday-Friday only
        if(dt.day_of_week == 0 || dt.day_of_week == 6)
            return false;

        // 00:00-23:00 GMT (forex nearly 24h)
        return true;
    }

    //+------------------------------------------------------------------+
    //| Get alert history                                               |
    //+------------------------------------------------------------------+
    void PrintAlertHistory(int count = 10)
    {
        Print("═══════════════════════════════════════════════════════════");
        Print("RECENT ALERT HISTORY");
        Print("═══════════════════════════════════════════════════════════");

        int display_count = MathMin(count, m_history_size);

        for(int i = 0; i < display_count; i++)
        {
            if(m_history[i].time == 0)
                break;

            string level_str = (m_history[i].level == ALERT_CRITICAL) ? "CRITICAL" :
                              (m_history[i].level == ALERT_WARNING) ? "WARNING" : "INFO";

            Print(StringFormat("[%d] %s | %s | %s",
                             i + 1,
                             TimeToString(m_history[i].time, TIME_DATE|TIME_MINUTES),
                             level_str,
                             m_history[i].message));
        }

        Print("═══════════════════════════════════════════════════════════");
    }

    //+------------------------------------------------------------------+
    //| Manual alert for custom conditions                              |
    //+------------------------------------------------------------------+
    void TriggerCustomAlert(string message, ENUM_ALERT_LEVEL level = ALERT_INFO)
    {
        SendAlert(message, level);
    }
};
