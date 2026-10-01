import { loadFont as loadPixel } from "@remotion/google-fonts/PixelifySans";
import { loadFont as loadBody } from "@remotion/google-fonts/Nunito";

export const pixelFont = loadPixel("normal", {
  weights: ["500", "700"],
  subsets: ["latin"],
}).fontFamily;
export const bodyFont = loadBody("normal", {
  weights: ["600", "800"],
  subsets: ["latin"],
}).fontFamily;

export const FPS = 30;

// The colony's own colours: Blocky's cast in AppSettings.defaultColors.
export const C = {
  bg: "#171a2b",
  bgGrid: "rgba(255,255,255,0.035)",
  ink: "#f6f1e7",
  dim: "#9aa0c3",
  bezel: "#2c3150",
  bezelLight: "#3d4470",
  outline: "#0e1020",
  paper: "#fff7e3",
  paperShade: "#e9dcbc",
  orange: "#ff8a3d",
  teal: "#3dc7b5",
  pink: "#ff6fa3",
  yellow: "#ffd23d",
  purple: "#9b7bff",
  green: "#7bd65a",
};
