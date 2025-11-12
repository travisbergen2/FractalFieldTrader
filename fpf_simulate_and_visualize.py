#!/usr/bin/env python3
"""
FPF Simulation and Visualization
Simulates J(P) = S + A coupling matrix dynamics and visualizes rotating spot behavior.
Matches the mathematical spec provided for FPF_Engine.mqh
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib import animation
from mpl_toolkits.mplot3d import Axes3D
from sklearn.decomposition import PCA
import os

# Parameters (same semantics as MQL5)
alpha, beta, gamma, kappa, lam = 0.5, 1.0, 0.6, 0.12, 0.8
delta, omega, phi, eta = 0.35, 1.2, 0.7, 0.45

def build_J(P):
    """Build coupling matrix J(P) = S + A"""
    n = len(P)
    m = np.mean(P)
    S = np.zeros((n, n))
    A = np.zeros((n, n))

    for i in range(n):
        for j in range(n):
            dij = abs(i - j)
            avg = 0.5 * (P[i] + P[j])
            diff = P[i] - P[j]

            # Symmetric component
            S[i, j] = alpha * avg * np.cos(beta * diff) * np.exp(-gamma * dij) * \
                     (1 + kappa * m * m) / (1 + lam * (abs(P[i]) + abs(P[j])) + 1e-12)

            # Antisymmetric component
            if i != j:
                k = (i + j) % n
                base = (P[i] - P[j])
                A[i, j] = delta * base * np.sin(omega * (P[i] + P[j]) + phi * P[k]) * \
                         np.exp(-eta * dij)

    # Enforce strict antisymmetry for A and symmetry for S
    for i in range(n):
        for j in range(i + 1, n):
            Ssym = 0.5 * (S[i, j] + S[j, i])
            S[i, j] = S[j, i] = Ssym
            a = 0.5 * (A[i, j] - A[j, i])
            A[i, j] = a
            A[j, i] = -a

    return S + A, S, A

def simulate(T=800, n=5, seed=1):
    """Simulate FPF state evolution over T time steps"""
    rng = np.random.RandomState(seed)
    P = rng.normal(0, 0.1, size=n)
    traj = []
    metrics = []

    for t in range(T):
        J, S, A = build_J(P)
        dt = 0.05
        dP = dt * (J.dot(P))
        noise = rng.normal(0, 0.005, size=n)
        P = P + dP + noise
        traj.append(P.copy())

        # Store metrics: norms
        metrics.append((np.linalg.norm(S), np.linalg.norm(A), np.linalg.norm(J)))

    return np.array(traj), np.array(metrics)

def make_3d_plot(traj, out="fpf_trajectory_3d.png"):
    """Create 3D trajectory plot using PCA"""
    pca = PCA(n_components=3)
    proj = pca.fit_transform(traj)

    fig = plt.figure(figsize=(10, 8))
    ax = fig.add_subplot(111, projection='3d')

    # Color by time
    colors = plt.cm.viridis(np.linspace(0, 1, len(proj)))
    for i in range(len(proj) - 1):
        ax.plot(proj[i:i+2, 0], proj[i:i+2, 1], proj[i:i+2, 2],
                color=colors[i], linewidth=1)

    ax.set_title('FPF State Trajectory (3D PCA projection)', fontsize=14, fontweight='bold')
    ax.set_xlabel('PC1')
    ax.set_ylabel('PC2')
    ax.set_zlabel('PC3')
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(out, dpi=150)
    plt.close()
    print(f"✅ Saved 3D trajectory plot: {out}")

def make_phase_plots(metrics, out_prefix="fpf"):
    """Plot S, A, J norms over time"""
    Snorm = metrics[:, 0]
    Anorm = metrics[:, 1]
    Jnorm = metrics[:, 2]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))

    # Norms over time
    ax1.plot(Snorm, label='||S|| (Resonance)', linewidth=2, alpha=0.8)
    ax1.plot(Anorm, label='||A|| (Orbital)', linewidth=2, alpha=0.8)
    ax1.plot(Jnorm, label='||J|| (Total)', linewidth=2, alpha=0.8, linestyle='--')
    ax1.set_ylabel('Norm', fontsize=12)
    ax1.set_title('FPF Field Intensity Over Time', fontsize=14, fontweight='bold')
    ax1.legend(fontsize=10)
    ax1.grid(True, alpha=0.3)

    # Orbital-to-resonance ratio
    orbital_ratio = Anorm / (Snorm + 1e-10)
    ax2.plot(orbital_ratio, color='purple', linewidth=2)
    ax2.axhline(1.0, color='red', linestyle='--', alpha=0.5, label='Equilibrium')
    ax2.set_xlabel('Time Step', fontsize=12)
    ax2.set_ylabel('Orbital / Resonance Ratio', fontsize=12)
    ax2.set_title('Market Regime Indicator', fontsize=14, fontweight='bold')
    ax2.legend(fontsize=10)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(out_prefix + "_norms.png", dpi=150)
    plt.close()
    print(f"✅ Saved norms plot: {out_prefix}_norms.png")

def animate_rotating_spot(traj, filename="fpf_rotation.mp4"):
    """Create animation of rotating spot in 2D phase space"""
    # Project trajectory to 2D for visualization
    pca = PCA(n_components=2)
    proj = pca.fit_transform(traj)
    x = proj[:, 0]
    y = proj[:, 1]

    fig, ax = plt.subplots(figsize=(8, 8))
    ax.set_xlim(x.min() - 0.5, x.max() + 0.5)
    ax.set_ylim(y.min() - 0.5, y.max() + 0.5)
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.set_title('FPF Rotating Spot Dynamics', fontsize=14, fontweight='bold')
    ax.set_xlabel('Phase Component 1', fontsize=12)
    ax.set_ylabel('Phase Component 2', fontsize=12)

    # Plot trail
    line, = ax.plot([], [], 'b-', lw=1, alpha=0.5)
    spot, = ax.plot([], [], 'ro', markersize=12)
    time_text = ax.text(0.02, 0.98, '', transform=ax.transAxes,
                        verticalalignment='top', fontsize=10,
                        bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

    # Circle to show range
    circle = plt.Circle((0, 0), np.max(np.sqrt(x**2 + y**2)),
                        color='gray', fill=False, linestyle='--', alpha=0.3)
    ax.add_patch(circle)

    def init():
        line.set_data([], [])
        spot.set_data([], [])
        time_text.set_text('')
        return line, spot, time_text

    def update(frame):
        # Show trail (last 50 points)
        start_idx = max(0, frame - 50)
        line.set_data(x[start_idx:frame], y[start_idx:frame])
        spot.set_data([x[frame]], [y[frame]])
        time_text.set_text(f'Step: {frame}/{len(x)}')
        return line, spot, time_text

    anim = animation.FuncAnimation(fig, update, frames=len(x), init_func=init,
                                   blit=True, interval=40)

    # Try to save as MP4
    try:
        Writer = animation.writers['ffmpeg']
        writer = Writer(fps=25, metadata=dict(artist='FPF'), bitrate=1800)
        anim.save(filename, writer=writer, dpi=150)
        print(f"✅ Saved animation: {filename}")
    except Exception as e:
        # Fallback: save as GIF
        try:
            anim.save(filename.replace('.mp4', '.gif'), writer='pillow', fps=25, dpi=100)
            print(f"✅ Saved animation (GIF): {filename.replace('.mp4', '.gif')}")
        except:
            print(f"⚠️  Could not save animation: {e}")
            print("   Install ffmpeg or pillow to enable animation export")

    plt.close()

def analyze_regime_transitions(traj, metrics):
    """Analyze regime changes based on orbital-to-resonance ratio"""
    Snorm = metrics[:, 0]
    Anorm = metrics[:, 1]

    orbital_ratio = Anorm / (Snorm + 1e-10)

    # Define regimes
    regimes = []
    for ratio in orbital_ratio:
        if ratio > 1.5:
            regimes.append('HIGH_ORBITAL')
        elif ratio < 0.5:
            regimes.append('HIGH_RESONANCE')
        else:
            regimes.append('BALANCED')

    # Count transitions
    transitions = 0
    for i in range(1, len(regimes)):
        if regimes[i] != regimes[i-1]:
            transitions += 1

    print(f"\n📊 Regime Analysis:")
    print(f"   Total time steps: {len(regimes)}")
    print(f"   Regime transitions: {transitions}")
    print(f"   High Orbital: {regimes.count('HIGH_ORBITAL')} ({regimes.count('HIGH_ORBITAL')/len(regimes)*100:.1f}%)")
    print(f"   High Resonance: {regimes.count('HIGH_RESONANCE')} ({regimes.count('HIGH_RESONANCE')/len(regimes)*100:.1f}%)")
    print(f"   Balanced: {regimes.count('BALANCED')} ({regimes.count('BALANCED')/len(regimes)*100:.1f}%)")

def create_phase_portrait_2d(traj, out="fpf_phase_portrait.png"):
    """Create 2D phase portrait with quadrant analysis"""
    pca = PCA(n_components=2)
    proj = pca.fit_transform(traj)

    fig, ax = plt.subplots(figsize=(10, 10))

    # Color by angular position
    angles = np.arctan2(proj[:, 1], proj[:, 0])
    colors = plt.cm.hsv((angles + np.pi) / (2 * np.pi))

    scatter = ax.scatter(proj[:, 0], proj[:, 1], c=colors, s=10, alpha=0.6)

    # Add quadrant lines
    ax.axhline(0, color='gray', linestyle='--', alpha=0.5)
    ax.axvline(0, color='gray', linestyle='--', alpha=0.5)

    # Label quadrants
    max_val = max(abs(proj[:, 0]).max(), abs(proj[:, 1]).max())
    ax.text(max_val * 0.7, max_val * 0.7, 'Q1: Risk-On', fontsize=12, ha='center')
    ax.text(-max_val * 0.7, max_val * 0.7, 'Q2: Volatile', fontsize=12, ha='center')
    ax.text(-max_val * 0.7, -max_val * 0.7, 'Q3: Risk-Off', fontsize=12, ha='center')
    ax.text(max_val * 0.7, -max_val * 0.7, 'Q4: Recovery', fontsize=12, ha='center')

    ax.set_xlabel('Phase Component 1', fontsize=12)
    ax.set_ylabel('Phase Component 2', fontsize=12)
    ax.set_title('FPF Phase Portrait (Colored by Angular Position)', fontsize=14, fontweight='bold')
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(out, dpi=150)
    plt.close()
    print(f"✅ Saved phase portrait: {out}")

def main():
    print("=" * 60)
    print("FPF SIMULATION AND VISUALIZATION")
    print("=" * 60)
    print(f"\nParameters:")
    print(f"  Symmetric:     α={alpha}, β={beta}, γ={gamma}, κ={kappa}, λ={lam}")
    print(f"  Antisymmetric: δ={delta}, ω={omega}, φ={phi}, η={eta}")
    print()

    # Run simulation
    print("Running simulation (1200 steps)...")
    traj, metrics = simulate(T=1200, n=5, seed=42)
    print(f"✅ Simulation complete")

    # Create visualizations
    print("\nGenerating visualizations...")
    make_3d_plot(traj, out="fpf_trajectory_3d.png")
    make_phase_plots(metrics, out_prefix="fpf")
    create_phase_portrait_2d(traj, out="fpf_phase_portrait.png")
    animate_rotating_spot(traj, filename="fpf_rotation.mp4")

    # Analyze regimes
    analyze_regime_transitions(traj, metrics)

    print("\n" + "=" * 60)
    print("✅ VISUALIZATION COMPLETE")
    print("=" * 60)
    print("\nGenerated files:")
    print("  - fpf_trajectory_3d.png (3D trajectory)")
    print("  - fpf_norms.png (field intensity over time)")
    print("  - fpf_phase_portrait.png (2D phase space)")
    print("  - fpf_rotation.mp4 (animated rotating spot)")
    print("\nUse these to understand FPF dynamics before trading!")

if __name__ == "__main__":
    main()
