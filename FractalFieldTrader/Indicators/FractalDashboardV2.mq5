//+------------------------------------------------------------------+
//| FractalDashboardV2.mq5                                           |
//| Enhanced visual dashboard with phase rotation and regime display|
//+------------------------------------------------------------------+
#property copyright "Fractal Field Trader V2"
#property version   "2.00"
#property indicator_chart_window
#property indicator_plots 0

#include <../Experts/FractalFieldTrader/Include/CoherenceMeasure.mqh>

// Input parameters
input int DashboardX = 20;
input int DashboardY = 80;
input bool ShowPhaseCircle = true;
input bool ShowRegimePanel = true;
input bool ShowSAMatrices = true;
input color ColorPhaseCircle = clrDodgerBlue;
input color ColorRegimeGood = clrLimeGreen;
input color ColorRegimeBad = clrRed;

// Global objects
CCoherenceMeasure* FieldEngine;
string ObjPrefix = "FPFv2_";

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════════════════════════");
    Print("FRACTAL DASHBOARD V2 - ADAPTIVE VISUALIZATION");
    Print("═══════════════════════════════════════════════════════════");

    FieldEngine = new CCoherenceMeasure();

    if(!FieldEngine.Init(_Symbol, PERIOD_CURRENT))
    {
        Print("❌ ERROR: Failed to initialize field engine");
        return INIT_FAILED;
    }

    CreateDashboard();

    Print("✅ Dashboard V2 ready");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DeleteDashboard();

    if(CheckPointer(FieldEngine) == POINTER_DYNAMIC)
        delete FieldEngine;

    Print("Dashboard V2 stopped");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    FieldEngine.Calculate();
    UpdateDashboard();

    return rates_total;
}

//+------------------------------------------------------------------+
//| Create all dashboard objects                                      |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int x = DashboardX;
    int y = DashboardY;

    // Main background panel
    CreateRectangle(ObjPrefix + "BG", x-10, y-60, x + 500, y + 450,
                    clrBlack, clrDimGray, 2);

    // Title
    CreateLabel(ObjPrefix + "Title", x + 150, y - 40,
                "FRACTAL FIELD DASHBOARD V2", clrWhite, 12, "Arial Bold");

    // === SECTION 1: FIELD STATE ===
    CreateLabel(ObjPrefix + "FieldTitle", x, y, "FIELD STATE", clrCyan, 11, "Arial Bold");

    CreateLabel(ObjPrefix + "CohLabel", x, y + 25, "Coherence:", clrWhite, 10, "Arial");
    CreateLabel(ObjPrefix + "CohValue", x + 110, y + 25, "0.0", clrLimeGreen, 10, "Arial Bold");

    CreateLabel(ObjPrefix + "AlignLabel", x, y + 45, "Alignment:", clrWhite, 10, "Arial");
    CreateLabel(ObjPrefix + "AlignValue", x + 110, y + 45, "0.0", clrLimeGreen, 10, "Arial Bold");

    CreateLabel(ObjPrefix + "StateLabel", x, y + 65, "State:", clrWhite, 10, "Arial");
    CreateLabel(ObjPrefix + "StateValue", x + 110, y + 65, "EMERGING", clrOrange, 10, "Arial Bold");

    // === SECTION 2: PHASE ROTATION ===
    if(ShowPhaseCircle)
    {
        int circle_y = y + 100;
        CreateLabel(ObjPrefix + "PhaseTitle", x, circle_y, "PHASE ROTATION", clrCyan, 11, "Arial Bold");

        // Phase circle background
        CreateCircle(ObjPrefix + "PhaseCircle", x + 100, circle_y + 50, 60, clrDarkSlateGray);

        // Quadrant labels
        CreateLabel(ObjPrefix + "Q1", x + 165, circle_y + 40, "INTENT", clrLightGray, 8, "Arial");
        CreateLabel(ObjPrefix + "Q2", x + 100, circle_y + 20, "MOMENTUM", clrLightGray, 8, "Arial");
        CreateLabel(ObjPrefix + "Q3", x + 35, circle_y + 40, "COGNITIVE", clrLightGray, 8, "Arial");
        CreateLabel(ObjPrefix + "Q4", x + 100, circle_y + 115, "EMOTION", clrLightGray, 8, "Arial");

        // Phase angle indicator (will be drawn as line)
        CreateLabel(ObjPrefix + "PhaseAngle", x, circle_y + 130, "Phase: 0°", clrYellow, 10, "Arial Bold");
        CreateLabel(ObjPrefix + "RotSpeed", x, circle_y + 150, "Rotation: 0.0°/bar", clrYellow, 9, "Arial");

        // Current phase name
        CreateLabel(ObjPrefix + "PhaseName", x, circle_y + 170, "NEUTRAL", clrWhite, 10, "Arial Bold");
    }

    // === SECTION 3: S/A MATRICES ===
    if(ShowSAMatrices)
    {
        int sa_y = y + 290;
        CreateLabel(ObjPrefix + "SATitle", x, sa_y, "S/A MATRIX", clrCyan, 11, "Arial Bold");

        // S-matrix (consensus)
        CreateLabel(ObjPrefix + "SLabel", x, sa_y + 25, "S (Consensus):", clrWhite, 10, "Arial");
        CreateLabel(ObjPrefix + "SValue", x + 130, sa_y + 25, "0.000", clrLimeGreen, 10, "Arial Bold");
        CreateRectangle(ObjPrefix + "SBar", x + 200, sa_y + 25, x + 200, sa_y + 40,
                       clrDarkGray, clrGray, 1);

        // A-matrix (rotation)
        CreateLabel(ObjPrefix + "ALabel", x, sa_y + 50, "A (Rotation):", clrWhite, 10, "Arial");
        CreateLabel(ObjPrefix + "AValue", x + 130, sa_y + 50, "0.000", clrOrange, 10, "Arial Bold");
        CreateRectangle(ObjPrefix + "ABar", x + 200, sa_y + 50, x + 200, sa_y + 65,
                       clrDarkGray, clrGray, 1);

        // Phi score
        CreateLabel(ObjPrefix + "PhiLabel", x, sa_y + 75, "Φ (Phi):", clrWhite, 10, "Arial");
        CreateLabel(ObjPrefix + "PhiValue", x + 130, sa_y + 75, "0.000", clrGold, 10, "Arial Bold");
    }

    // === SECTION 4: REGIME STATUS ===
    if(ShowRegimePanel)
    {
        int regime_y = y + 380;
        CreateLabel(ObjPrefix + "RegimeTitle", x, regime_y, "TEMPORAL REGIME", clrCyan, 11, "Arial Bold");
        CreateLabel(ObjPrefix + "RegimeValue", x, regime_y + 25, "INITIALIZING", clrYellow, 11, "Arial Bold");
        CreateLabel(ObjPrefix + "AlphaLabel", x, regime_y + 50, "α (Alpha):", clrWhite, 9, "Arial");
        CreateLabel(ObjPrefix + "AlphaValue", x + 70, regime_y + 50, "0.1000", clrCyan, 9, "Arial Bold");
    }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update dashboard with current values                              |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    int x = DashboardX;
    int y = DashboardY;

    // Get field metrics
    double coh = FieldEngine.GetOverallCoherence();
    double align = FieldEngine.GetFieldAlignment();
    string field_state = FieldEngine.GetFieldState();

    // Update field state
    ObjectSetString(0, ObjPrefix + "CohValue", OBJPROP_TEXT, DoubleToString(coh, 1));
    ObjectSetString(0, ObjPrefix + "AlignValue", OBJPROP_TEXT, DoubleToString(align, 1));
    ObjectSetString(0, ObjPrefix + "StateValue", OBJPROP_TEXT, field_state);

    // Color coding
    color coh_color = (coh > 70) ? clrLimeGreen : (coh > 55) ? clrYellow : clrOrange;
    ObjectSetInteger(0, ObjPrefix + "CohValue", OBJPROP_COLOR, coh_color);

    // Update phase rotation
    if(ShowPhaseCircle)
    {
        double phase_angle = FieldEngine.GetPhaseAngle();
        double rotation_speed = FieldEngine.GetRotationSpeed();
        string current_phase = FieldEngine.GetCurrentPhase();

        ObjectSetString(0, ObjPrefix + "PhaseAngle", OBJPROP_TEXT,
                       "Phase: " + DoubleToString(phase_angle, 1) + "°");
        ObjectSetString(0, ObjPrefix + "RotSpeed", OBJPROP_TEXT,
                       "Rotation: " + DoubleToString(rotation_speed, 1) + "°/bar");
        ObjectSetString(0, ObjPrefix + "PhaseName", OBJPROP_TEXT, current_phase);

        // Draw phase indicator line (simplified - using arrow)
        DrawPhaseArrow(x + 100, y + 150, phase_angle, 50);
    }

    // Update S/A matrices
    if(ShowSAMatrices)
    {
        CIntentionalState* intent = FieldEngine.GetIntentionalEngine();
        CEmotionalState* emo = FieldEngine.GetEmotionalEngine();

        if(CheckPointer(intent) != POINTER_INVALID && CheckPointer(emo) != POINTER_INVALID)
        {
            double buy = intent.GetBuyPressure();
            double sell = intent.GetSellPressure();
            double greed = emo.GetGreedLevel();
            double fear = emo.GetFearLevel();

            // Calculate S/A (simplified formula)
            double s_strength = (coh / 100.0) * (align / 100.0) * (MathMax(buy, sell) / 100.0);
            double a_strength = ((buy + sell) / 200.0) * (1.0 - MathAbs(buy - sell) / 100.0);
            double phi = (s_strength * 0.7) + (a_strength * 0.3);

            int sa_y = y + 290;

            ObjectSetString(0, ObjPrefix + "SValue", OBJPROP_TEXT, DoubleToString(s_strength, 3));
            ObjectSetString(0, ObjPrefix + "AValue", OBJPROP_TEXT, DoubleToString(a_strength, 3));
            ObjectSetString(0, ObjPrefix + "PhiValue", OBJPROP_TEXT, DoubleToString(phi, 3));

            // Update S bar
            int s_width = (int)(s_strength * 200);
            ObjectDelete(0, ObjPrefix + "SBar");
            CreateRectangle(ObjPrefix + "SBar", x + 200, sa_y + 25, x + 200 + s_width, sa_y + 40,
                           clrLimeGreen, clrLimeGreen, 0);

            // Update A bar
            int a_width = (int)(a_strength * 200);
            ObjectDelete(0, ObjPrefix + "ABar");
            CreateRectangle(ObjPrefix + "ABar", x + 200, sa_y + 50, x + 200 + a_width, sa_y + 65,
                           clrOrange, clrOrange, 0);
        }
    }

    // Update regime status (would need adaptive filter integration)
    if(ShowRegimePanel)
    {
        // Placeholder - would connect to adaptive filter
        string regime = "DETECTING";
        double alpha = 0.1;

        int regime_y = y + 380;
        ObjectSetString(0, ObjPrefix + "RegimeValue", OBJPROP_TEXT, regime);
        ObjectSetString(0, ObjPrefix + "AlphaValue", OBJPROP_TEXT, DoubleToString(alpha, 4));
    }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Draw phase arrow indicator                                        |
//+------------------------------------------------------------------+
void DrawPhaseArrow(int center_x, int center_y, double angle, int length)
{
    // Convert angle to radians
    double angle_rad = angle * M_PI / 180.0;

    // Calculate endpoint (MetaTrader uses screen coordinates)
    int end_x = center_x + (int)(length * MathCos(angle_rad));
    int end_y = center_y - (int)(length * MathSin(angle_rad));  // Negative because screen Y increases downward

    // Create trend line for phase indicator
    string arrow_name = ObjPrefix + "PhaseArrow";
    ObjectDelete(0, arrow_name);

    // Create arrow object
    ObjectCreate(0, arrow_name, OBJ_ARROW, 0, 0, 0);
    ObjectSetInteger(0, arrow_name, OBJPROP_ARROWCODE, 241);  // Arrow symbol
    ObjectSetInteger(0, arrow_name, OBJPROP_COLOR, clrYellow);
    ObjectSetInteger(0, arrow_name, OBJPROP_WIDTH, 3);
    ObjectSetInteger(0, arrow_name, OBJPROP_BACK, false);
    ObjectSetInteger(0, arrow_name, OBJPROP_SELECTABLE, false);

    // Position at calculated endpoint
    ObjectSetInteger(0, arrow_name, OBJPROP_XDISTANCE, end_x);
    ObjectSetInteger(0, arrow_name, OBJPROP_YDISTANCE, end_y);
}

//+------------------------------------------------------------------+
//| Delete all dashboard objects                                      |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
    ObjectsDeleteAll(0, ObjPrefix);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: Create label                                             |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int size, string font)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper: Create rectangle                                         |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x1, int y1, int x2, int y2,
                     color fill_color, color border_color, int border_width)
{
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x1);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y1);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, x2 - x1);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, y2 - y1);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill_color);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border_color);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, border_width);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper: Create circle (using ellipse)                            |
//+------------------------------------------------------------------+
void CreateCircle(string name, int center_x, int center_y, int radius, color fill_color)
{
    // Create ellipse as circle
    ObjectCreate(0, name, OBJ_ELLIPSE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, center_x - radius);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, center_y - radius);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, radius * 2);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, radius * 2);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill_color);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
