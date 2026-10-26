import React from "react";
import {
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { At, Prop, Species, Stars, lift } from "../../sprites";
import { Backdrop, Chip, ChipRow, Headline, clamp } from "../../ui";
import { C, pixelFont } from "../../theme";
import { jump } from "../../scenes/Intro";

const PW = 540;
const PH = 280;
const S = 3;
const FLOOR = PH - 6;
const STAND = FLOOR - lift(S);

/** The way something running back and forth along a sine faces: its speed's sign. */
const facingLeft = (t: number, period: number) => Math.cos(t / period) < 0;

const Tag: React.FC<{ t: number }> = ({ t }) => {
  const run = (sp: Species, lag: number, seed: number) => {
    const u = t - lag;
    return (
      <At
        species={sp}
        x={270 + 200 * Math.sin(u / 18)}
        y={STAND}
        scale={S}
        flip={facingLeft(u, 18)}
        pose="walk"
        seed={seed}
      />
    );
  };
  return (
    <>
      {run("cat", 0, 1)}
      {run("blocky", 9, 2)}
    </>
  );
};

const Rope: React.FC<{ t: number }> = ({ t }) => {
  const a = 0.85 * Math.sin(t / 13);
  const L = 160;
  const hx = 270;
  const hy = 26;
  const x = hx + L * Math.sin(a);
  const y = hy + L * Math.cos(a);
  return (
    <>
      <Prop frame="hook" x={hx} y={hy} scale={S} />
      <div
        style={{
          position: "absolute",
          left: hx - 3,
          top: hy,
          width: 6,
          height: L - 20,
          background: "#c9a26b",
          boxShadow: `0 0 0 2px ${C.outline}`,
          transformOrigin: "3px 0",
          transform: `rotate(${(-a * 180) / Math.PI}deg)`,
        }}
      />
      <At
        species="frog"
        x={x}
        y={y}
        angle={(-a * 180) / Math.PI}
        scale={S}
        flip={Math.cos(t / 13) < 0}
        pose="jump"
        seed={3}
      />
    </>
  );
};

const Parachute: React.FC<{ t: number }> = ({ t }) => {
  const u = t % 120;
  const y = interpolate(u, [0, 90], [-60, STAND], {
    ...clamp,
    easing: Easing.out(Easing.quad),
  });
  const landed = u >= 90;
  const sway = landed ? 0 : Math.sin(u / 7) * 8;
  const x = 270 + sway * 3;
  return (
    <>
      {!landed && (
        <Prop frame="chute" x={x} y={y - 64} scale={S} angle={sway} />
      )}
      <At
        species="ghost"
        x={x}
        y={y}
        angle={sway}
        scale={S}
        pose={landed ? (u < 96 ? "land" : "idle") : "jump"}
        seed={4}
      />
    </>
  );
};

const Basketball: React.FC<{ t: number }> = ({ t }) => {
  const u = t % 64;
  const p = u / 40;
  const shooter = 110;
  const rim = { x: 432, y: 104 };
  const inAir = p <= 1;
  const bx = inAir ? 140 + (rim.x - 140) * p : rim.x;
  const by = inAir
    ? 150 + (rim.y - 150) * p - 150 * Math.sin(Math.PI * p)
    : rim.y + (u - 40) * 6;
  const score = Math.floor(t / 64) + (u >= 42 ? 1 : 0);
  return (
    <>
      <Prop
        frame={u >= 40 && u < 50 ? "hoop-swish" : "hoop"}
        x={455}
        y={110}
        scale={S}
      />
      <At
        species="robot"
        x={shooter}
        y={STAND - jump(u, 40)}
        scale={S}
        pose={u < 18 ? "jump" : "idle"}
        seed={5}
      />
      {by < FLOOR - 10 && (
        <Prop
          frame={Math.floor(t / 4) % 2 ? "ball-1" : "ball-0"}
          x={bx}
          y={by}
          scale={S}
        />
      )}
      <Score text={`${score}`} />
    </>
  );
};

const Soccer: React.FC<{ t: number }> = ({ t }) => {
  // Back and forth between the two, then a long kick into the left net.
  const goal = 150;
  const pass = t < goal;
  const ph = (t % 40) / 40;
  const leg = Math.floor(t / 40) % 2;
  const from = leg ? 380 : 170;
  const to = leg ? 170 : 380;
  const bx = pass
    ? from + (to - from) * ph
    : interpolate(t, [goal, goal + 24], [380, 50], clamp);
  const ballY = FLOOR - 16;
  return (
    <>
      <Prop frame="net" x={36} y={FLOOR - 70} scale={S} />
      <Prop frame="net" x={504} y={FLOOR - 70} scale={S} flip />
      <At
        species="blocky-pip"
        x={150}
        y={STAND - (t > goal + 2 && t < goal + 22 ? jump(t - goal - 2, 50) : 0)}
        scale={S}
        seed={6}
      />
      <At
        species="slime"
        x={400}
        y={STAND - (t > goal + 30 ? jump((t - goal - 30) % 26, 40) : 0)}
        scale={S}
        flip
        seed={7}
      />
      <Prop
        frame={Math.floor(t / 4) % 2 ? "soccer-1" : "soccer-0"}
        x={bx}
        y={ballY}
        scale={S}
      />
      <Stars x={60} y={FLOOR - 60} at={goal + 24} />
      <Score text={t >= goal + 24 ? "2–1" : "1–1"} />
    </>
  );
};

const Baseball: React.FC<{ t: number }> = ({ t }) => {
  const bases = [80, 270, 460];
  const leg = Math.min(2, Math.floor(t / 44));
  const u = Math.min(1, (t - leg * 44) / 24);
  const from = bases[Math.max(0, leg - 1)];
  const to = bases[leg];
  const x = leg === 0 ? bases[0] : from + (to - from) * Math.max(0, u);
  const hop = leg > 0 && u < 1 ? 90 * Math.sin(Math.PI * u) : 0;
  const hit = t < 34 ? t / 34 : 1;
  return (
    <>
      {bases.map((b, i) => (
        <Prop
          key={b}
          frame={i === leg && (leg === 0 || u >= 1) ? "base-taken" : "base"}
          x={b}
          y={FLOOR - 14}
          scale={S}
        />
      ))}
      <Prop frame="bat" x={120} y={STAND - 10} scale={S} angle={-40 * hit} />
      {t > 6 && t < 60 && (
        <Prop
          frame="baseball"
          x={130 + (t - 6) * 9}
          y={STAND - (t - 6) * 6}
          scale={S}
        />
      )}
      <At
        species="triangle"
        x={x}
        y={STAND - 18 - hop}
        scale={S}
        pose={hop > 0 ? "jump" : "idle"}
        seed={8}
      />
      <Score
        text={leg === 2 && u >= 1 ? "THIRD" : leg === 1 ? "SECOND" : "HIT"}
      />
    </>
  );
};

const Score: React.FC<{ text: string }> = ({ text }) => (
  <div
    style={{
      position: "absolute",
      right: 14,
      top: 12,
      padding: "4px 12px",
      background: C.outline,
      color: C.yellow,
      fontFamily: pixelFont,
      fontWeight: 700,
      fontSize: 24,
    }}
  >
    {text}
  </div>
);

const GAMES: { name: string; colour: string; Game: React.FC<{ t: number }> }[] =
  [
    { name: "TAG", colour: C.pink, Game: Tag },
    { name: "NINJA ROPE", colour: C.green, Game: Rope },
    { name: "PARACHUTE", colour: C.purple, Game: Parachute },
    { name: "BASKETBALL", colour: C.orange, Game: Basketball },
    { name: "SOCCER", colour: C.teal, Game: Soccer },
    { name: "BASEBALL", colour: C.yellow, Game: Baseball },
  ];

export const Games: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Backdrop>
      <Headline
        kicker="04 · PLAYTIME"
        title="Six games, more often between friends"
        colour={C.green}
      />
      {GAMES.map(({ name, colour, Game }, i) => {
        const at = 8 + i * 10;
        const pop = spring({
          frame: f - at,
          fps,
          config: { damping: 13, stiffness: 150 },
        });
        const col = i % 3;
        const row = Math.floor(i / 3);
        return (
          <div
            key={name}
            style={{
              position: "absolute",
              left: 105 + col * (PW + 45),
              top: 290 + row * (PH + 56),
              width: PW,
              height: PH,
              background:
                "linear-gradient(160deg, #2f3a73 0%, #5a4c8f 55%, #c0729a 100%)",
              border: `6px solid ${C.bezel}`,
              boxShadow: `0 0 0 4px ${C.outline}, 0 20px 40px rgba(0,0,0,0.4)`,
              transform: `scale(${pop})`,
              opacity: Math.min(1, pop * 1.5),
            }}
          >
            <div
              style={{
                position: "absolute",
                inset: 0,
                overflow: "hidden",
              }}
            >
              <Game t={Math.max(0, f - at)} />
            </div>
            <div
              style={{
                position: "absolute",
                left: 14,
                top: -24,
                padding: "4px 12px",
                background: colour,
                color: C.outline,
                fontFamily: pixelFont,
                fontWeight: 700,
                fontSize: 24,
                border: `4px solid ${C.outline}`,
              }}
            >
              {name}
            </div>
          </div>
        );
      })}
      <ChipRow>
        <Chip at={60} colour={C.teal}>
          Teams, best friends together
        </Chip>
        <Chip at={110} colour={C.yellow}>
          A pixel scoreboard
        </Chip>
        <Chip at={160} colour={C.pink}>
          Cheers in each one&apos;s voice
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
