//+------------------------------------------------------------------+
//| FPF_Engine.mqh                                                   |
//| Implements J(P) = S + A coupling matrix (symmetric + antisym)    |
//| Phase Field Predictor with rotating spot dynamics                |
//+------------------------------------------------------------------+
#ifndef __FPF_ENGINE_MQH__
#define __FPF_ENGINE_MQH__

#include "Matrix.mqh"

//+------------------------------------------------------------------+
//| FPF Engine - manages coupling matrix and state evolution        |
//+------------------------------------------------------------------+
class CFPFEngine
{
private:
    // Parameters (tunable)
    double m_alpha;   // Symmetric resonance strength
    double m_beta;    // Sensitivity to differences
    double m_gamma;   // Spatial attenuation
    double m_kappa;   // Global resonance gain
    double m_lambda;  // Local amplitude normalization

    double m_delta;   // Antisymmetric strength
    double m_omega;   // Orbital frequency multiplier
    double m_phi;     // Third-axis phase influence
    double m_eta;     // Antisymm attenuation by distance

    int m_n;          // Number of dimensions (5)

    CMatrix m_J;      // Full coupling matrix J = S + A
    CMatrix m_S;      // Symmetric component
    CMatrix m_A;      // Antisymmetric component

    double m_P[];     // Current state vector (5D)
    double m_P_prev[];// Previous state for velocity

    double m_S_norm;  // ||S|| - resonance intensity
    double m_A_norm;  // ||A|| - orbital intensity
    double m_J_norm;  // ||J|| - total field intensity

    double m_spot_x;  // Rotating spot position (2D projection)
    double m_spot_y;
    double m_angular_velocity; // Rotation speed

public:
    CFPFEngine()
    {
        // Default parameters from the spec
        m_alpha = 0.5;
        m_beta = 1.0;
        m_gamma = 0.6;
        m_kappa = 0.12;
        m_lambda = 0.8;

        m_delta = 0.35;
        m_omega = 1.2;
        m_phi = 0.7;
        m_eta = 0.45;

        m_n = 5;

        m_J.Resize(m_n, m_n);
        m_S.Resize(m_n, m_n);
        m_A.Resize(m_n, m_n);

        ArrayResize(m_P, m_n);
        ArrayResize(m_P_prev, m_n);
        ArrayInitialize(m_P, 0.0);
        ArrayInitialize(m_P_prev, 0.0);

        m_S_norm = 0.0;
        m_A_norm = 0.0;
        m_J_norm = 0.0;
        m_spot_x = 0.0;
        m_spot_y = 0.0;
        m_angular_velocity = 0.0;
    }

    ~CFPFEngine() {}

    // Set parameters
    void SetParameters(double alpha, double beta, double gamma, double kappa, double lambda,
                      double delta, double omega, double phi, double eta)
    {
        m_alpha = alpha; m_beta = beta; m_gamma = gamma; m_kappa = kappa; m_lambda = lambda;
        m_delta = delta; m_omega = omega; m_phi = phi; m_eta = eta;
    }

    // Update state vector from market data
    void UpdateState(double temporal, double emotional, double cognitive, double social, double intentional)
    {
        // Store previous state
        for(int i = 0; i < m_n; i++)
            m_P_prev[i] = m_P[i];

        // Update current state (normalized to reasonable range)
        m_P[0] = (temporal - 50.0) / 50.0;      // -1 to 1
        m_P[1] = (emotional - 50.0) / 50.0;
        m_P[2] = (cognitive - 50.0) / 50.0;
        m_P[3] = (social - 50.0) / 50.0;
        m_P[4] = (intentional - 50.0) / 50.0;
    }

    // Generate coupling matrices J = S + A
    void GenerateCouplingMatrix()
    {
        // Compute mean
        double m = 0.0;
        for(int r = 0; r < m_n; r++)
            m += m_P[r];
        m /= (double)m_n;

        // Zero matrices
        m_S.Zero();
        m_A.Zero();

        // Build symmetric and antisymmetric components
        for(int i = 0; i < m_n; i++)
        {
            for(int j = 0; j < m_n; j++)
            {
                int dij = MathAbs(i - j);
                double avg = 0.5 * (m_P[i] + m_P[j]);
                double diff = (m_P[i] - m_P[j]);

                // Symmetric component S_ij
                double cosTerm = MathCos(m_beta * diff);
                double attenuation = MathExp(-m_gamma * dij);
                double normalization = 1.0 + m_lambda * (MathAbs(m_P[i]) + MathAbs(m_P[j]));
                double S_ij = m_alpha * avg * cosTerm * attenuation * (1.0 + m_kappa * m * m) / normalization;
                m_S.Set(i, j, S_ij);

                // Antisymmetric component A_ij
                if(i == j)
                {
                    m_A.Set(i, j, 0.0);
                }
                else
                {
                    int k = (i + j) % m_n; // Third-axis phase coupling
                    double base = (m_P[i] - m_P[j]);
                    double sinTerm = MathSin(m_omega * (m_P[i] + m_P[j]) + m_phi * m_P[k]);
                    double attenA = MathExp(-m_eta * dij);
                    double A_ij = m_delta * base * sinTerm * attenA;
                    m_A.Set(i, j, A_ij);
                }
            }
        }

        // Enforce strict symmetry for S and antisymmetry for A
        for(int i = 0; i < m_n; i++)
        {
            for(int j = i + 1; j < m_n; j++)
            {
                // Make S symmetric
                double Ssym = 0.5 * (m_S.Get(i, j) + m_S.Get(j, i));
                m_S.Set(i, j, Ssym);
                m_S.Set(j, i, Ssym);

                // Make A antisymmetric
                double a = 0.5 * (m_A.Get(i, j) - m_A.Get(j, i));
                m_A.Set(i, j, a);
                m_A.Set(j, i, -a);
            }
        }

        // Combine into J
        for(int i = 0; i < m_n; i++)
            for(int j = 0; j < m_n; j++)
                m_J.Set(i, j, m_S.Get(i, j) + m_A.Get(i, j));

        // Compute norms
        m_S_norm = m_S.FrobeniusNorm();
        m_A_norm = m_A.FrobeniusNorm();
        m_J_norm = m_J.FrobeniusNorm();

        // Compute spot position (PCA projection approximation - use first 2 components)
        m_spot_x = m_P[0] * 0.447 + m_P[1] * 0.447 + m_P[2] * 0.447;  // Simplified
        m_spot_y = m_P[3] * 0.707 - m_P[4] * 0.707;

        // Estimate angular velocity
        double prev_angle = MathArctan2(m_P_prev[3] - m_P_prev[4], m_P_prev[0] + m_P_prev[1] + m_P_prev[2]);
        double curr_angle = MathArctan2(m_P[3] - m_P[4], m_P[0] + m_P[1] + m_P[2]);
        m_angular_velocity = curr_angle - prev_angle;

        // Normalize to [-pi, pi]
        if(m_angular_velocity > M_PI) m_angular_velocity -= 2 * M_PI;
        else if(m_angular_velocity < -M_PI) m_angular_velocity += 2 * M_PI;
    }

    // Advance state by one step (simple Euler integration)
    void AdvanceState(double dt = 0.05, double noise_level = 0.005)
    {
        double dP[];
        m_J.MultVector(m_P, dP);

        for(int i = 0; i < m_n; i++)
        {
            double noise = (MathRand() / 16384.0 - 1.0) * noise_level;
            m_P[i] += dt * dP[i] + noise;

            // Clamp to reasonable range
            m_P[i] = MathMax(-2.0, MathMin(2.0, m_P[i]));
        }
    }

    // Get orbital-to-resonance ratio (key trading metric)
    double GetOrbitalRatio() const
    {
        if(m_S_norm < 1e-6) return 0.0;
        return m_A_norm / m_S_norm;
    }

    // Get coherence indicator (high S_norm = stable resonance)
    double GetResonanceIntensity() const { return m_S_norm; }

    // Get rotation indicator (high A_norm = strong orbital flow)
    double GetOrbitalIntensity() const { return m_A_norm; }

    // Get field strength
    double GetFieldIntensity() const { return m_J_norm; }

    // Get spot coordinates
    double GetSpotX() const { return m_spot_x; }
    double GetSpotY() const { return m_spot_y; }
    double GetAngularVelocity() const { return m_angular_velocity; }

    // Get state vector
    void GetState(double &P[]) const
    {
        ArrayResize(P, m_n);
        ArrayCopy(P, m_P);
    }

    // Get feature vector for ML (11 features)
    void GetFeatures(double &features[]) const
    {
        ArrayResize(features, 11);

        // State mean and std
        double mean = 0.0, variance = 0.0;
        for(int i = 0; i < m_n; i++)
            mean += m_P[i];
        mean /= m_n;

        for(int i = 0; i < m_n; i++)
            variance += MathPow(m_P[i] - mean, 2);
        variance /= m_n;
        double std = MathSqrt(variance);

        // State velocity (magnitude of change)
        double velocity = 0.0;
        for(int i = 0; i < m_n; i++)
            velocity += MathPow(m_P[i] - m_P_prev[i], 2);
        velocity = MathSqrt(velocity);

        features[0] = mean;
        features[1] = std;
        features[2] = velocity;
        features[3] = m_S_norm;
        features[4] = m_A_norm;
        features[5] = m_J_norm;
        features[6] = GetOrbitalRatio();
        features[7] = m_spot_x;
        features[8] = m_spot_y;
        features[9] = m_angular_velocity;
        features[10] = MathSqrt(m_spot_x * m_spot_x + m_spot_y * m_spot_y); // spot radius
    }

    // Print diagnostics
    void PrintDiagnostics() const
    {
        Print("=== FPF Engine State ===");
        Print("  S_norm (resonance): ", DoubleToString(m_S_norm, 4));
        Print("  A_norm (orbital):   ", DoubleToString(m_A_norm, 4));
        Print("  J_norm (total):     ", DoubleToString(m_J_norm, 4));
        Print("  Orbital/Resonance:  ", DoubleToString(GetOrbitalRatio(), 4));
        Print("  Spot (x,y):         ", DoubleToString(m_spot_x, 4), ", ", DoubleToString(m_spot_y, 4));
        Print("  Angular velocity:   ", DoubleToString(m_angular_velocity, 4));
        Print("  State P: [", DoubleToString(m_P[0], 3), ", ", DoubleToString(m_P[1], 3), ", ",
              DoubleToString(m_P[2], 3), ", ", DoubleToString(m_P[3], 3), ", ", DoubleToString(m_P[4], 3), "]");
    }
};

#endif // __FPF_ENGINE_MQH__
