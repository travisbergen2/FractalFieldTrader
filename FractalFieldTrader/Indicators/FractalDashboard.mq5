//+------------------------------------------------------------------+
//| FractalDashboard.mq5                                             |
//| Visual dashboard for Fractal Personality Field analysis          |
//+------------------------------------------------------------------+
#property copyright "Fractal Field Trader"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include <../Experts/FractalFieldTrader/Include/GradientAnalyzer.mqh>

// Input parameters
input int DashboardX = 20;           // X position from left
input int DashboardY = 80;           // Y position from top
input int BarWidth = 60;             // Width of coherence bars
input int BarHeight = 150;           // Height of coherence bars
input bool ShowSubDimensions = true; // Show T/E/C/S scores
input color ColorChaos = clrDarkRed;
input color ColorOrder = clrDarkOrange;
input color ColorComplexity = clrDodgerBlue;
input color ColorEmergence = clrLimeGreen;
input color ColorTranscendence = clrGold;

// Global objects
CGradientAnalyzer* GradientEngine;

// Dashboard object names
string ObjPrefix = "FPF_";

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== FRACTAL DASHBOARD INITIALIZING ===");
    
    // Create gradient analyzer
    GradientEngine = new CGradientAnalyzer();
    
    if(!GradientEngine.Init(_Symbol))
    {
        Print("ERROR: Failed to initialize gradient engine");
        return INIT_FAILED;
    }
    
    // Create dashboard objects
    CreateDashboard();
    
    Print("=== DASHBOARD READY ===");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up objects
    DeleteDashboard();
    
    // Delete gradient engine
    if(CheckPointer(GradientEngine) == POINTER_DYNAMIC)
        delete GradientEngine;
    
    Print("Dashboard stopped");
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
    // Update analysis
    GradientEngine.AnalyzeAllScales(_Symbol);
    
    // Update dashboard visuals
    UpdateDashboard();
    
    return rates_total;
}

//+------------------------------------------------------------------+
//| Timer event - update every second                                |
//+------------------------------------------------------------------+
void OnTimer()
{
    GradientEngine.AnalyzeAllScales(_Symbol);
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Create all dashboard objects                                      |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int x = DashboardX;
    int y = DashboardY;
    
    // Background panel
    CreateRectangle(ObjPrefix + "BG", x-10, y-60, x + (BarWidth * 6) + 70, y + BarHeight + 180, 
                    clrBlack, clrDimGray, 2);
    
    // Title
    CreateLabel(ObjPrefix + "Title", x + 150, y - 40, "FRACTAL FIELD ANALYSIS", 
                clrWhite, 12, "Arial Bold");
    
    // Timeframe labels
    string timeframes[] = {"M5", "M15", "H1", "H4", "D1", "W1"};
    for(int i = 0; i < 6; i++)
    {
        int bar_x = x + (i * (BarWidth + 10));
        CreateLabel(ObjPrefix + "TF_" + IntegerToString(i), bar_x + 15, y - 20, 
                    timeframes[i], clrWhite, 10, "Arial Bold");
    }
    
    // Create coherence bars (will be updated with values)
    for(int i = 0; i < 6; i++)
    {
        int bar_x = x + (i * (BarWidth + 10));
        CreateRectangle(ObjPrefix + "Bar_" + IntegerToString(i), 
                        bar_x, y + BarHeight, bar_x + BarWidth, y + BarHeight, 
                        clrDarkGray, clrGray, 1);
        
        // Coherence value label
        CreateLabel(ObjPrefix + "Val_" + IntegerToString(i), bar_x + 15, y + BarHeight + 5,
                    "0", clrWhite, 9, "Arial");
        
        // Sub-dimension labels (T, E, C, S)
        if(ShowSubDimensions)
        {
            CreateLabel(ObjPrefix + "T_" + IntegerToString(i), bar_x + 5, y + BarHeight + 25,
                        "T:0", clrLightGray, 7, "Arial");
            CreateLabel(ObjPrefix + "E_" + IntegerToString(i), bar_x + 5, y + BarHeight + 38,
                        "E:0", clrLightGray, 7, "Arial");
            CreateLabel(ObjPrefix + "C_" + IntegerToString(i), bar_x + 5, y + BarHeight + 51,
                        "C:0", clrLightGray, 7, "Arial");
        }
    }
    
    // Flow direction
    CreateLabel(ObjPrefix + "FlowLabel", x, y + BarHeight + 80, "FLOW:", clrWhite, 10, "Arial Bold");
    CreateLabel(ObjPrefix + "FlowValue", x + 60, y + BarHeight + 80, "---", clrYellow, 10, "Arial Bold");
    
    // Alignment meter
    CreateLabel(ObjPrefix + "AlignLabel", x, y + BarHeight + 100, "ALIGNMENT:", clrWhite, 10, "Arial Bold");
    CreateLabel(ObjPrefix + "AlignValue", x + 110, y + BarHeight + 100, "0.00", clrCyan, 10, "Arial Bold");
    CreateRectangle(ObjPrefix + "AlignBar", x + 180, y + BarHeight + 100, x + 180, y + BarHeight + 115,
                    clrDarkGray, clrGray, 1);
    
    // Transition state
    CreateLabel(ObjPrefix + "TransLabel", x, y + BarHeight + 125, "TRANSITION:", clrWhite, 10, "Arial Bold");
    CreateLabel(ObjPrefix + "TransValue", x + 110, y + BarHeight + 125, "STABLE", clrLightGray, 10, "Arial Bold");
    
    // Rung indicator
    CreateLabel(ObjPrefix + "RungLabel", x, y + BarHeight + 150, "FIELD STATE:", clrWhite, 10, "Arial Bold");
    CreateLabel(ObjPrefix + "RungValue", x + 110, y + BarHeight + 150, "ORDER", clrOrange, 11, "Arial Bold");
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update dashboard with current values                              |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    int x = DashboardX;
    int y = DashboardY;
    
    double avg_coherence = GradientEngine.GetAverageCoherence();
    string flow = GradientEngine.DetectFlowDirection();
    double alignment = GradientEngine.MeasureScaleAlignment();
    string transition = GradientEngine.DetectTransitionSignature();
    
    // Update each timeframe bar
    for(int i = 0; i < 6; i++)
    {
        // Get state for this timeframe
        double coherence = GetTimeframeCoherence(i);
        double temporal = GetTimeframeTemporal(i);
        double emotional = GetTimeframeEmotional(i);
        double cognitive = GetTimeframeCognitive(i);
        
        // Calculate bar height based on coherence (0-100)
        int bar_height = (int)((coherence / 100.0) * BarHeight);
        
        // Determine color based on coherence level (Rung mapping)
        color bar_color = GetCoherenceColor(coherence);
        
        // Update bar
        int bar_x = x + (i * (BarWidth + 10));
        ObjectDelete(0, ObjPrefix + "Bar_" + IntegerToString(i));
        CreateRectangle(ObjPrefix + "Bar_" + IntegerToString(i),
                        bar_x, y + BarHeight - bar_height, 
                        bar_x + BarWidth, y + BarHeight,
                        bar_color, bar_color, 0);
        
        // Update coherence value
        ObjectSetString(0, ObjPrefix + "Val_" + IntegerToString(i), OBJPROP_TEXT, 
                        DoubleToString(coherence, 1));
        
        // Update sub-dimensions
        if(ShowSubDimensions)
        {
            ObjectSetString(0, ObjPrefix + "T_" + IntegerToString(i), OBJPROP_TEXT,
                            "T:" + DoubleToString(temporal, 0));
            ObjectSetString(0, ObjPrefix + "E_" + IntegerToString(i), OBJPROP_TEXT,
                            "E:" + DoubleToString(emotional, 0));
            ObjectSetString(0, ObjPrefix + "C_" + IntegerToString(i), OBJPROP_TEXT,
                            "C:" + DoubleToString(cognitive, 0));
        }
    }
    
    // Update flow direction
    ObjectSetString(0, ObjPrefix + "FlowValue", OBJPROP_TEXT, flow);
    color flow_color = (flow == "BOTTOM_UP") ? clrLime : 
                       (flow == "TOP_DOWN") ? clrOrange : clrRed;
    ObjectSetInteger(0, ObjPrefix + "FlowValue", OBJPROP_COLOR, flow_color);
    
    // Update alignment
    ObjectSetString(0, ObjPrefix + "AlignValue", OBJPROP_TEXT, 
                    DoubleToString(alignment, 2));
    
    // Update alignment bar
    int align_bar_width = (int)(alignment * 200);
    ObjectDelete(0, ObjPrefix + "AlignBar");
    CreateRectangle(ObjPrefix + "AlignBar", 
                    x + 180, y + BarHeight + 100,
                    x + 180 + align_bar_width, y + BarHeight + 115,
                    clrCyan, clrCyan, 0);
    
    // Update transition
    ObjectSetString(0, ObjPrefix + "TransValue", OBJPROP_TEXT, transition);
    color trans_color = (transition == "COMPLEXITY_TO_EMERGENCE") ? clrLime :
                        (transition == "EMERGENCE_TO_CHAOS") ? clrRed :
                        (transition == "CHAOS_TO_ORDER") ? clrYellow : clrLightGray;
    ObjectSetInteger(0, ObjPrefix + "TransValue", OBJPROP_COLOR, trans_color);
    
    // Update Rung/State
    string state = GetFieldState(avg_coherence);
    ObjectSetString(0, ObjPrefix + "RungValue", OBJPROP_TEXT, state);
    ObjectSetInteger(0, ObjPrefix + "RungValue", OBJPROP_COLOR, GetCoherenceColor(avg_coherence));
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Get coherence color based on Rung                                |
//+------------------------------------------------------------------+
color GetCoherenceColor(double coherence)
{
    if(coherence < 30)
        return ColorChaos;        // Rung 0: Chaos
    else if(coherence < 50)
        return ColorOrder;        // Rung 1: Order
    else if(coherence < 70)
        return ColorComplexity;   // Rung 2: Complexity
    else if(coherence < 90)
        return ColorEmergence;    // Rung 3: Emergence
    else
        return ColorTranscendence; // Rung 4: Transcendence
}

//+------------------------------------------------------------------+
//| Get field state name from coherence                              |
//+------------------------------------------------------------------+
string GetFieldState(double coherence)
{
    if(coherence < 30)
        return "CHAOS";
    else if(coherence < 50)
        return "ORDER";
    else if(coherence < 70)
        return "COMPLEXITY";
    else if(coherence < 90)
        return "EMERGENCE";
    else
        return "TRANSCENDENCE";
}

//+------------------------------------------------------------------+
//| Helper to get timeframe coherence (accessing private data)       |
//+------------------------------------------------------------------+
double GetTimeframeCoherence(int tf_index)
{
    // This is a workaround - we'll need to expose this in GradientAnalyzer
    // For now, recalculate (inefficient but works)
    static double cache[6] = {0};
    
    ENUM_TIMEFRAMES tfs[6] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};
    
    CCoherenceMeasure temp_engine(50);
    temp_engine.Init(_Symbol, tfs[tf_index]);
    cache[tf_index] = temp_engine.Calculate(_Symbol, tfs[tf_index]);
    
    return cache[tf_index];
}

double GetTimeframeTemporal(int tf_index)
{
    ENUM_TIMEFRAMES tfs[6] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};
    CCoherenceMeasure temp_engine(50);
    temp_engine.Init(_Symbol, tfs[tf_index]);
    temp_engine.Calculate(_Symbol, tfs[tf_index]);
    return temp_engine.GetTemporalScore();
}

double GetTimeframeEmotional(int tf_index)
{
    ENUM_TIMEFRAMES tfs[6] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};
    CCoherenceMeasure temp_engine(50);
    temp_engine.Init(_Symbol, tfs[tf_index]);
    temp_engine.Calculate(_Symbol, tfs[tf_index]);
    return temp_engine.GetEmotionalScore();
}

double GetTimeframeCognitive(int tf_index)
{
    ENUM_TIMEFRAMES tfs[6] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};
    CCoherenceMeasure temp_engine(50);
    temp_engine.Init(_Symbol, tfs[tf_index]);
    temp_engine.Calculate(_Symbol, tfs[tf_index]);
    return temp_engine.GetCognitiveScore();
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