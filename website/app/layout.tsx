import type { Metadata } from "next";
import { Poppins, Inter } from "next/font/google";
import "./globals.css";

const display = Poppins({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-display",
});

const body = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-body",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://calllane.hardeep.cv"),
  title: "CallLane: keep your music loud during Mac calls",
  description:
    "A free, open-source menu-bar app that stops macOS from quieting everything else during calls, and keeps your AirPods at full quality.",
  openGraph: {
    title: "CallLane: keep your music loud during Mac calls",
    description:
      "Free, open-source menu-bar app. Music stays at full volume during FaceTime, WhatsApp, Zoom, Meet, Slack, Teams and Discord. AirPods keep their listening quality.",
    url: "https://calllane.hardeep.cv",
    siteName: "CallLane",
    images: [{ url: "/panel-light.png", width: 680, height: 680 }],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  );
}
