//+------------------------------------------------------------------+
//| Matrix.mqh - Simple matrix operations for FPF coupling          |
//+------------------------------------------------------------------+

class CMatrix
{
private:
    double m_data[][];
    int m_rows;
    int m_cols;

public:
    CMatrix() : m_rows(0), m_cols(0) {}

    CMatrix(int rows, int cols)
    {
        Resize(rows, cols);
    }

    ~CMatrix() {}

    void Resize(int rows, int cols)
    {
        m_rows = rows;
        m_cols = cols;
        ArrayResize(m_data, m_rows);
        for(int i = 0; i < m_rows; i++)
        {
            ArrayResize(m_data[i], m_cols);
            for(int j = 0; j < m_cols; j++)
                m_data[i][j] = 0.0;
        }
    }

    void Set(int i, int j, double value)
    {
        if(i >= 0 && i < m_rows && j >= 0 && j < m_cols)
            m_data[i][j] = value;
    }

    double Get(int i, int j) const
    {
        if(i >= 0 && i < m_rows && j >= 0 && j < m_cols)
            return m_data[i][j];
        return 0.0;
    }

    int Rows() const { return m_rows; }
    int Cols() const { return m_cols; }

    // Matrix-vector multiplication: result = M * v
    void MultVector(const double &v[], double &result[])
    {
        if(ArraySize(v) != m_cols) return;
        ArrayResize(result, m_rows);

        for(int i = 0; i < m_rows; i++)
        {
            result[i] = 0.0;
            for(int j = 0; j < m_cols; j++)
                result[i] += m_data[i][j] * v[j];
        }
    }

    // Frobenius norm
    double FrobeniusNorm() const
    {
        double sum = 0.0;
        for(int i = 0; i < m_rows; i++)
            for(int j = 0; j < m_cols; j++)
                sum += m_data[i][j] * m_data[i][j];
        return MathSqrt(sum);
    }

    // Power iteration for spectral norm approximation
    double SpectralNorm(int iterations = 20) const
    {
        if(m_rows == 0 || m_cols == 0) return 0.0;

        double v[]; ArrayResize(v, m_cols);
        double w[]; ArrayResize(w, m_rows);

        // Initialize random vector
        for(int i = 0; i < m_cols; i++)
            v[i] = (MathRand() / 32767.0) - 0.5;

        // Normalize
        double norm = 0.0;
        for(int i = 0; i < m_cols; i++)
            norm += v[i] * v[i];
        norm = MathSqrt(norm);
        if(norm < 1e-10) norm = 1.0;
        for(int i = 0; i < m_cols; i++)
            v[i] /= norm;

        // Power iteration
        for(int iter = 0; iter < iterations; iter++)
        {
            // w = M * v
            for(int i = 0; i < m_rows; i++)
            {
                w[i] = 0.0;
                for(int j = 0; j < m_cols; j++)
                    w[i] += m_data[i][j] * v[j];
            }

            // Normalize w
            double s = 0.0;
            for(int i = 0; i < m_rows; i++)
                s += w[i] * w[i];
            s = MathSqrt(s);
            if(s < 1e-10) break;

            // v = w / ||w||
            for(int i = 0; i < MathMin(m_rows, m_cols); i++)
                v[i] = w[i] / s;
        }

        // Rayleigh quotient
        double numer = 0.0, denom = 0.0;
        for(int i = 0; i < m_rows; i++)
        {
            double mv = 0.0;
            for(int j = 0; j < m_cols; j++)
                mv += m_data[i][j] * v[j];
            numer += w[i] * mv;
        }
        for(int i = 0; i < MathMin(m_rows, m_cols); i++)
            denom += v[i] * v[i];

        if(denom < 1e-10) return 0.0;
        return MathAbs(numer / denom);
    }

    void Zero()
    {
        for(int i = 0; i < m_rows; i++)
            for(int j = 0; j < m_cols; j++)
                m_data[i][j] = 0.0;
    }

    void Print() const
    {
        for(int i = 0; i < m_rows; i++)
        {
            string row = "";
            for(int j = 0; j < m_cols; j++)
                row += StringFormat("%.4f ", m_data[i][j]);
            ::Print(row);
        }
    }
};
