//+------------------------------------------------------------------+
//|                                ConsciousnessCircle_v2_ZField.mq5 |
//|                                      Fractal Youniverse Framework|
//|                   Rotating Dot + Z-Field Confidence Filtering    |
//+------------------------------------------------------------------+
#property copyright "Travis Bergen - FYF"
#property link      "https://fractalyouniverse.com"
#property version   "2.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Input parameters
input group "=== DISPLAY SETTINGS ==="
input int      CircleRadius = 100;
input int      CircleX = 150;
input int      CircleY = 150;
input bool     ShowPredictionTrail = true;
input int      TrailLength = 8;
input bool     ShowZFieldMeter = true;

input group "=== Z-FIELD SETTINGS ==="
input bool     EnableZFieldFilter = true;
input double   ZThreshold = 1.5;
input double   AlphaWeight = 1.0;
input double   BetaWeight = 1.0;
input double   GammaWeight = 1.0;
input double   DeltaWeight = 0.5;
input double   EpsilonWeight = 1.0;
input double   ZetaWeight = 1.0;

input group "=== DYNAMICS SETTINGS ==="
input int      LookbackPeriod = 100;

// FIXED: Changed enum name to avoid conflict
enum DimensionPairType {
    EW_PAIR,   // Emotion-Will
    CT_PAIR,   // Cognition-Time
    ES_PAIR,   // Emotion-Social
    CW_PAIR    // Cognition-Will
};
input DimensionPairType ActiveDimPair = EW_PAIR;  // FIXED: Changed variable name

input group "=== ALERT SETTINGS ==="
input bool     AlertOnQuadrantChange = true;
input bool     AlertOnHighSpeed = true;
input double   HighSpeedThreshold = 0.15;
input bool     AlertOnColorChange = true;
input bool     AlertOnHighZField = true;
input double   HighZFieldLevel = 3.0;

input group "=== ADVANCED ==="
input double   Kappa = 0.20;
input double   AlphaCE = 0.30;
input double   AlphaWS = -0.25;
input double   AlphaTC = 0.25;
input double   RhoEW = 0.35;
input double   RhoWT = 0.30;
input double   RhoTE = 0.25;

//--- Global variables
struct State {
    double C, E, W, S, T;
};

datetime lastUpdate = 0;
int lastQuadrant = 0;
int lastDotColor = 0;
double currentPhase = 0;
double currentOmega = 0;
double currentZField = 0;
double PsiHistory[2];

//--- Object names
string objCircle = "ConsciousnessCircle";
string objDot = "ConsciousnessDot";
string objCenterH = "CenterLineH";
string objCenterV = "CenterLineV";
string objLabelBull = "LabelBull";
string objLabelBear = "LabelBear";
string objLabelQ1 = "LabelQ1";
string objLabelQ2 = "LabelQ2";
string objLabelQ3 = "LabelQ3";
string objLabelQ4 = "LabelQ4";
string objSpeedMeter = "SpeedMeter";
string objZFieldMeter = "ZFieldMeter";
string objZFieldBar = "ZFieldBar";
string objTrail = "Trail_";

//+------------------------------------------------------------------+
int OnInit()
{
    ArrayInitialize(PsiHistory, 0);
    CreateCircleVisualization();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectDelete(0, objCircle);
    ObjectDelete(0, objDot);
    ObjectDelete(0, objCenterH);
    ObjectDelete(0, objCenterV);
    ObjectDelete(0, objLabelBull);
    ObjectDelete(0, objLabelBear);
    ObjectDelete(0, objLabelQ1);
    ObjectDelete(0, objLabelQ2);
    ObjectDelete(0, objLabelQ3);
    ObjectDelete(0, objLabelQ4);
    ObjectDelete(0, objSpeedMeter);
    ObjectDelete(0, objZFieldMeter);
    ObjectDelete(0, objZFieldBar);

    for(int i = 0; i < TrailLength; i++) {
        ObjectDelete(0, objTrail + IntegerToString(i));
    }
}

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
    if(rates_total < LookbackPeriod) return(0);

    int current = rates_total - 1;

    if(time[current] == lastUpdate) return(rates_total);
    lastUpdate = time[current];

    // Calculate personality state
    State state;
    CalcPersonality(current, high, low, close, tick_volume, state);

    // Calculate Z-field
    double Z = CalculateZField(current, high, low, close, tick_volume, state);
    currentZField = Z;

    // Get active dimensions
    double dim1, dim2;
    GetDimensions(state, dim1, dim2);

    // Calculate phase angle
    double phase = MathArctan2(dim2, dim1);
    if(phase < 0) phase += 2*M_PI;

    // Calculate angular velocity
    double prevPhase = currentPhase;
    double dphase = phase - prevPhase;
    if(dphase > M_PI) dphase -= 2*M_PI;
    if(dphase < -M_PI) dphase += 2*M_PI;
    currentOmega = dphase;
    currentPhase = phase;

    // Calculate sensory alignment
    double alignment = CalcAlignment(state);

    // Z-FIELD FILTER
    if(EnableZFieldFilter && MathAbs(Z) < ZThreshold) {
        alignment = 0.0;
    }

    // Update visualization
    UpdateDotPosition(phase, alignment, Z);
    UpdateSpeedMeter(currentOmega);

    if(ShowZFieldMeter) {
        UpdateZFieldDisplay(Z);
    }

    if(ShowPredictionTrail) {
        UpdatePredictionTrail(state, phase, current, tick_volume);
    }

    CheckAlerts(phase, alignment, currentOmega, Z, time[current]);

    return(rates_total);
}

//+------------------------------------------------------------------+
double CalculateZField(int i, const double &h[], const double &l[],
                       const double &c[], const long &v[], State &s)
{
    // Ψ: Baseline field
    double ema21 = 0, ema55 = 0;
    int count21 = 0, count55 = 0;

    for(int j = 0; j < 21 && i-j >= 0; j++) {
        ema21 += c[i-j];
        count21++;
    }
    for(int j = 0; j < 55 && i-j >= 0; j++) {
        ema55 += c[i-j];
        count55++;
    }

    ema21 = (count21 > 0) ? ema21 / count21 : c[i];
    ema55 = (count55 > 0) ? ema55 / count55 : c[i];

    double Psi = (ema21 - ema55) / c[i] * 100;

    PsiHistory[1] = PsiHistory[0];
    PsiHistory[0] = Psi;

    // dΨ/dt
    double dPsi_dt = Psi - PsiHistory[1];

    // N: Cognitive
    double N = s.C;

    // S: Somatic
    double atr = 0;
    int atr_count = 0;
    for(int j = 0; j < 14 && i-j >= 1; j++) {
        double tr = MathMax(h[i-j] - l[i-j],
                    MathMax(MathAbs(h[i-j] - c[i-j-1]),
                            MathAbs(l[i-j] - c[i-j-1])));
        atr += tr;
        atr_count++;
    }
    double S = (atr_count > 0 && c[i] > 0) ? (atr / atr_count) / c[i] * 100 : 0;

    // Q: Quantum
    double Q = CalculateFractalDimension(i, h, l);

    // η: Heart
    double eta = s.E;

    // E: Environment
    double vRatio = 1.0;
    if(i > 0 && v[i-1] > 0) {
        vRatio = (double)v[i] / (double)v[i-1];
    }
    double E = MathLog(vRatio + 0.1);

    // Z-FIELD EQUATION
    double Z = Psi
             + AlphaWeight * dPsi_dt
             + BetaWeight * N
             + GammaWeight * S
             + DeltaWeight * Q
             + EpsilonWeight * eta
             + ZetaWeight * E;

    return Z;
}

//+------------------------------------------------------------------+
double CalculateFractalDimension(int i, const double &h[], const double &l[])
{
    double ranges[10];
    int count = 0;

    for(int j = 0; j < 10 && i-j >= 0; j++) {
        ranges[count] = h[i-j] - l[i-j];
        count++;
    }

    if(count == 0) return 1.5;

    double avg = 0;
    for(int j = 0; j < count; j++) avg += ranges[j];
    avg /= count;

    if(avg == 0) return 1.5;

    double variance = 0;
    for(int j = 0; j < count; j++) {
        variance += MathPow(ranges[j] - avg, 2);
    }
    variance /= count;

    double fractal = 1.0 + MathSqrt(variance) / avg;
    return MathMax(1.0, MathMin(2.0, fractal));
}

//+------------------------------------------------------------------+
void UpdateZFieldDisplay(double Z)
{
    string zText = StringFormat("Z-Field: %.2f | ", Z);

    if(MathAbs(Z) < ZThreshold) {
        zText += "⚠️ LOW CONFIDENCE";
    }
    else if(Z > HighZFieldLevel) {
        zText += "🚀 EXTREME BULLISH";
    }
    else if(Z < -HighZFieldLevel) {
        zText += "💥 EXTREME BEARISH";
    }
    else if(Z > ZThreshold) {
        zText += "✅ BULLISH";
    }
    else {
        zText += "✅ BEARISH";
    }

    if(ObjectFind(0, objZFieldMeter) < 0) {
        CreateLabel(objZFieldMeter, zText, CircleX, CircleY + CircleRadius + 50, clrWhite, ANCHOR_CENTER);
    }
    ObjectSetString(0, objZFieldMeter, OBJPROP_TEXT, zText);

    color zColor;
    if(MathAbs(Z) < ZThreshold) zColor = clrGray;
    else if(Z > HighZFieldLevel) zColor = clrLime;
    else if(Z < -HighZFieldLevel) zColor = clrRed;
    else if(Z > 0) zColor = clrLightGreen;
    else zColor = clrPink;

    ObjectSetInteger(0, objZFieldMeter, OBJPROP_COLOR, zColor);

    DrawZFieldBar(Z);
}

//+------------------------------------------------------------------+
void DrawZFieldBar(double Z)
{
    int barY = CircleY + CircleRadius + 70;
    int barX = CircleX - 100;
    int barWidth = 200;
    int barHeight = 10;

    string objBG = objZFieldBar + "_BG";
    if(ObjectFind(0, objBG) < 0) {
        ObjectCreate(0, objBG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objBG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objBG, OBJPROP_XDISTANCE, barX);
        ObjectSetInteger(0, objBG, OBJPROP_YDISTANCE, barY);
        ObjectSetInteger(0, objBG, OBJPROP_XSIZE, barWidth);
        ObjectSetInteger(0, objBG, OBJPROP_YSIZE, barHeight);
        ObjectSetInteger(0, objBG, OBJPROP_BGCOLOR, clrDarkGray);
        ObjectSetInteger(0, objBG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }

    double zNorm = Z / 10.0;
    zNorm = MathMax(-1.0, MathMin(1.0, zNorm));

    int fillWidth = (int)(MathAbs(zNorm) * barWidth / 2);
    int fillX = (Z > 0) ? barX + barWidth/2 : barX + barWidth/2 - fillWidth;

    if(ObjectFind(0, objZFieldBar) < 0) {
        ObjectCreate(0, objZFieldBar, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objZFieldBar, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objZFieldBar, OBJPROP_YSIZE, barHeight);
        ObjectSetInteger(0, objZFieldBar, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }

    ObjectSetInteger(0, objZFieldBar, OBJPROP_XDISTANCE, fillX);
    ObjectSetInteger(0, objZFieldBar, OBJPROP_YDISTANCE, barY);
    ObjectSetInteger(0, objZFieldBar, OBJPROP_XSIZE, fillWidth);

    color fillColor = (Z > 0) ? clrLime : clrRed;
    ObjectSetInteger(0, objZFieldBar, OBJPROP_BGCOLOR, fillColor);
}

//+------------------------------------------------------------------+
void CreateCircleVisualization()
{
    int r = CircleRadius;
    int cx = CircleX;
    int cy = CircleY;

    CreateLabel(objCircle, "⭕", cx, cy - r, clrRed, ANCHOR_CENTER);
    ObjectSetInteger(0, objCircle, OBJPROP_FONTSIZE, (int)(r * 2.5));

    CreateLabel(objDot, "●", cx, cy, clrCyan, ANCHOR_CENTER);
    ObjectSetInteger(0, objDot, OBJPROP_FONTSIZE, 20);

    CreateLabel(objLabelBull, "BULL", cx + r + 20, cy - 5, clrLime, ANCHOR_LEFT);
    CreateLabel(objLabelBear, "BEAR", cx - r - 50, cy - 5, clrRed, ANCHOR_LEFT);

    CreateLabel(objLabelQ1, "Q1: Risk-On", cx + r/2, cy - r/2 - 20, clrLightGreen, ANCHOR_CENTER);
    CreateLabel(objLabelQ2, "Q2: Volatile", cx - r/2, cy - r/2 - 20, clrOrange, ANCHOR_CENTER);
    CreateLabel(objLabelQ3, "Q3: Risk-Off", cx - r/2, cy + r/2 + 20, clrPink, ANCHOR_CENTER);
    CreateLabel(objLabelQ4, "Q4: Recovery", cx + r/2, cy + r/2 + 20, clrYellow, ANCHOR_CENTER);

    CreateLabel(objSpeedMeter, "Speed: 0.00", cx, cy + r + 30, clrWhite, ANCHOR_CENTER);
}

//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, ENUM_ANCHOR_POINT anchor)
{
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }
}

//+------------------------------------------------------------------+
void UpdateDotPosition(double phase, double alignment, double Z)
{
    int r = CircleRadius;
    int centerX = CircleX;
    int centerY = CircleY;

    int dotX = centerX + (int)(r * MathCos(phase));
    int dotY = centerY - (int)(r * MathSin(phase));

    ObjectSetInteger(0, objDot, OBJPROP_XDISTANCE, dotX);
    ObjectSetInteger(0, objDot, OBJPROP_YDISTANCE, dotY);

    color dotColor;
    int newColor;

    if(EnableZFieldFilter && MathAbs(Z) < ZThreshold) {
        dotColor = clrYellow;
        newColor = 0;
    }
    else if(alignment > 0.5) {
        dotColor = clrLime;
        newColor = 1;
    }
    else if(alignment < -0.5) {
        dotColor = clrRed;
        newColor = 2;
    }
    else {
        dotColor = clrYellow;
        newColor = 0;
    }

    ObjectSetInteger(0, objDot, OBJPROP_COLOR, dotColor);
    lastDotColor = newColor;
}

//+------------------------------------------------------------------+
void UpdateSpeedMeter(double omega)
{
    string speedText = StringFormat("Rotation: %.3f rad/bar | ", MathAbs(omega));

    double absOmega = MathAbs(omega);
    if(absOmega > 0.20)
        speedText += "VERY FAST ⚡";
    else if(absOmega > 0.10)
        speedText += "FAST 🔥";
    else if(absOmega > 0.05)
        speedText += "MODERATE 🌊";
    else
        speedText += "SLOW 🐌";

    ObjectSetString(0, objSpeedMeter, OBJPROP_TEXT, speedText);

    color speedColor;
    if(absOmega > 0.15) speedColor = clrRed;
    else if(absOmega > 0.08) speedColor = clrOrange;
    else speedColor = clrLightGray;

    ObjectSetInteger(0, objSpeedMeter, OBJPROP_COLOR, speedColor);
}

//+------------------------------------------------------------------+
void UpdatePredictionTrail(State &current, double phase, int idx, const long &v[])
{
    double P[5] = {current.C, current.E, current.W, current.S, current.T};
    double dt = CalcChronoception(idx, v);

    for(int step = 1; step <= TrailLength; step++) {
        double dP[5];
        CalcDerivatives(P, dP);

        for(int i = 0; i < 5; i++) {
            P[i] += dt * dP[i];
            P[i] = MathMax(-1.0, MathMin(1.0, P[i]));
        }

        State pred = {P[0], P[1], P[2], P[3], P[4]};
        double d1, d2;
        GetDimensions(pred, d1, d2);
        double predPhase = MathArctan2(d2, d1);
        if(predPhase < 0) predPhase += 2*M_PI;

        string trailName = objTrail + IntegerToString(step);

        int r = CircleRadius;
        int centerX = CircleX;
        int centerY = CircleY;

        int trailX = centerX + (int)(r * MathCos(predPhase));
        int trailY = centerY - (int)(r * MathSin(predPhase));

        if(ObjectFind(0, trailName) < 0) {
            ObjectCreate(0, trailName, OBJ_LABEL, 0, 0, 0);
            ObjectSetString(0, trailName, OBJPROP_TEXT, "•");
            ObjectSetInteger(0, trailName, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, trailName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        }

        ObjectSetInteger(0, trailName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, trailName, OBJPROP_XDISTANCE, trailX);
        ObjectSetInteger(0, trailName, OBJPROP_YDISTANCE, trailY);
        ObjectSetInteger(0, trailName, OBJPROP_COLOR, clrDimGray);
    }
}

//+------------------------------------------------------------------+
void CheckAlerts(double phase, double alignment, double omega, double Z, datetime t)
{
    int quad = GetQuadrant(phase);

    if(AlertOnQuadrantChange && quad != lastQuadrant) {
        Alert("🔄 ", GetQuadName(quad), " | Z=", DoubleToString(Z, 2));
        PlaySound("alert.wav");
        lastQuadrant = quad;
    }

    if(AlertOnHighSpeed && MathAbs(omega) > HighSpeedThreshold) {
        Alert("⚡ HIGH SPEED | Z=", DoubleToString(Z, 2));
        PlaySound("alert2.wav");
    }

    int currentColor = (alignment > 0.5) ? 1 : (alignment < -0.5) ? 2 : 0;
    if(AlertOnColorChange && currentColor != lastDotColor && currentColor != 0) {
        string msg = (currentColor == 1) ? "🟢 BULLISH!" : "🔴 BEARISH!";
        Alert(msg, " | Z=", DoubleToString(Z, 2));
        PlaySound("alert2.wav");
    }

    if(AlertOnHighZField && MathAbs(Z) > HighZFieldLevel) {
        string zMsg = (Z > 0) ? "🚀 EXTREME BULL Z!" : "💥 EXTREME BEAR Z!";
        Alert(zMsg, " Z=", DoubleToString(Z, 2));
        PlaySound("alert.wav");
    }
}

//+------------------------------------------------------------------+
int GetQuadrant(double phase)
{
    if(phase >= 0 && phase < M_PI/2) return 1;
    if(phase >= M_PI/2 && phase < M_PI) return 2;
    if(phase >= M_PI && phase < 3*M_PI/2) return 3;
    return 4;
}

//+------------------------------------------------------------------+
string GetQuadName(int q)
{
    switch(q) {
        case 1: return "Q1: Risk-On";
        case 2: return "Q2: Volatile";
        case 3: return "Q3: Risk-Off";
        case 4: return "Q4: Recovery";
    }
    return "";
}

//+------------------------------------------------------------------+
void CalcPersonality(int i, const double &h[], const double &l[],
                     const double &c[], const long &v[], State &s)
{
    double range = 0;
    for(int j = 0; j < 10 && i-j >= 0; j++) range += h[i-j] - l[i-j];
    range /= 10;
    s.C = MathTanh(range / c[i] * 100 - 1.5);

    double atr = 0;
    for(int j = 0; j < 14 && i-j >= 1; j++) {
        double tr = MathMax(h[i-j] - l[i-j],
                    MathMax(MathAbs(h[i-j] - c[i-j-1]),
                            MathAbs(l[i-j] - c[i-j-1])));
        atr += tr;
    }
    atr /= 14;
    s.E = MathTanh((atr / c[i]) * 100 - 1.0);

    double mom = (i >= 20) ? (c[i] - c[i-20]) / c[i-20] : 0;
    s.W = MathTanh(mom * 100);

    double gains = 0, losses = 0;
    for(int j = 0; j < 14 && i-j >= 1; j++) {
        double chg = c[i-j] - c[i-j-1];
        if(chg > 0) gains += chg;
        else losses += MathAbs(chg);
    }
    double rsi = (losses == 0) ? 100 : 100 - 100/(1 + gains/losses);
    s.S = (rsi - 50) / 50.0;

    double vr = (i > 0 && v[i-1] > 0) ? (double)v[i] / (double)v[i-1] : 1.0;
    s.T = MathTanh(MathLog(vr + 0.1));
}

//+------------------------------------------------------------------+
void GetDimensions(State &s, double &d1, double &d2)
{
    // FIXED: Use the renamed input variable
    switch(ActiveDimPair) {
        case EW_PAIR: d1 = s.E; d2 = s.W; break;
        case CT_PAIR: d1 = s.C; d2 = s.T; break;
        case ES_PAIR: d1 = s.E; d2 = s.S; break;
        case CW_PAIR: d1 = s.C; d2 = s.W; break;
    }
}

//+------------------------------------------------------------------+
double CalcAlignment(State &s)
{
    double senses[5] = {s.C, s.E, s.W, s.S, s.T};
    int bull = 0, bear = 0;

    for(int i = 0; i < 5; i++) {
        if(senses[i] > 0.3) bull++;
        if(senses[i] < -0.3) bear++;
    }

    if(bull >= 4) return 1.0;
    if(bear >= 4) return -1.0;
    return 0.0;
}

//+------------------------------------------------------------------+
double CalcChronoception(int i, const long &v[])
{
    double avg = 0;
    int cnt = 0;
    for(int j = 0; j < LookbackPeriod && i-j >= 0; j++) {
        avg += (double)v[i-j];
        cnt++;
    }
    avg /= cnt;

    double ratio = (avg > 0) ? (double)v[i] / avg : 1.0;
    return MathMax(0.1, MathMin(3.0, MathExp(0.5 * MathLog(ratio + 0.1))));
}

//+------------------------------------------------------------------+
void CalcDerivatives(double &P[], double &dP[])
{
    double J[5][5];
    BuildCoupling(P, J);

    for(int i = 0; i < 5; i++) {
        dP[i] = -Kappa * P[i];
        for(int j = 0; j < 5; j++)
            dP[i] += J[i][j] * P[j];
    }
}

//+------------------------------------------------------------------+
void BuildCoupling(double &P[], double &J[][5])
{
    ArrayInitialize(J, 0.0);

    double S_CE = AlphaCE * MathTanh(1.5 * P[0] * P[1]);
    J[0][1] = S_CE; J[1][0] = S_CE;

    double S_WS = AlphaWS * MathTanh(1.5 * P[2] * P[3]);
    J[2][3] = S_WS; J[3][2] = S_WS;

    double S_TC = AlphaTC * MathTanh(1.2 * P[4] * P[0]);
    J[4][0] = S_TC; J[0][4] = S_TC;

    double A_EW = RhoEW * MathTanh(1.2 * P[1]);
    J[2][1] = A_EW; J[1][2] = -A_EW;

    double A_WT = RhoWT * MathTanh(1.2 * P[2]);
    J[4][2] = A_WT; J[2][4] = -A_WT;

    double A_TE = RhoTE * MathTanh(1.2 * P[4]);
    J[1][4] = A_TE; J[4][1] = -A_TE;
}
//+------------------------------------------------------------------+
