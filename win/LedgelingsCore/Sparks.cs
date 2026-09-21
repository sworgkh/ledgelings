namespace Ledgelings.Core;

/// <summary>A handful of pixel stars thrown up when two creatures bump. They fly into
/// the screen, fall back toward the edge, and fade within a second.</summary>
public sealed class Sparks
{
    public sealed class Spark
    {
        public Pt Position;
        public Vec Velocity;
        /// <summary>Which way "down" is for this star: back toward its edge.</summary>
        public Vec Gravity;
        public double Age;
        public double Life;
        /// <summary>0, 1, 2…: lets the renderer vary the colour without the logic caring.</summary>
        public int Tint;

        public double Opacity => Math.Max(0, 1 - Age / Life);
    }

    public double Life { get; set; }
    public (double Low, double High) Speed { get; set; }
    public double Pull { get; set; }
    private readonly List<Spark> alive = new();
    public IReadOnlyList<Spark> Alive => alive;

    public Sparks(double life = 0.7, (double Low, double High)? speed = null, double pull = 300)
    {
        Life = life;
        Speed = speed ?? (70, 150);
        Pull = pull;
    }

    /// <summary>Fan <paramref name="count"/> stars out around <paramref name="inward"/>, within 60° either side of it.</summary>
    public void Burst(Pt point, Vec inward, int count, Random rng)
    {
        var baseAngle = Math.Atan2(inward.Dy, inward.Dx);
        for (int k = 0; k < count; k++)
        {
            var angle = baseAngle + rng.Range(-Math.PI / 3, Math.PI / 3);
            var v = rng.Range(Speed);
            alive.Add(new Spark
            {
                Position = point,
                Velocity = new Vec(Math.Cos(angle) * v, Math.Sin(angle) * v),
                Gravity = new Vec(-inward.Dx * Pull, -inward.Dy * Pull),
                Life = Life * rng.Range(0.7, 1.1),
                Tint = k,
            });
        }
    }

    public void Update(double dt)
    {
        foreach (var s in alive)
        {
            s.Velocity = new Vec(s.Velocity.Dx + s.Gravity.Dx * dt, s.Velocity.Dy + s.Gravity.Dy * dt);
            s.Position = new Pt(s.Position.X + s.Velocity.Dx * dt, s.Position.Y + s.Velocity.Dy * dt);
            s.Age += dt;
        }
        alive.RemoveAll(s => s.Age >= s.Life);
    }
}
