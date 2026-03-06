import { useState } from "react";

const HOUSE_STYLE_POSITIVE = `1970s comic book illustration, retro pulp print look, bold black ink outlines, clean confident linework, flat cel shading, subtle halftone / newsprint texture, limited warm palette (cream, tan, muted earth tones) with slightly richer midtones, clear value contrast and hard-edged shadows, simple graphic composition, no readable text`;

const HOUSE_STYLE_NEGATIVE = `photorealistic, 3d render, soft gradients, painterly, watercolor, neon colors, modern digital art, anime, manga, bright saturated colors, glowing effects, fantasy lighting, blur, bokeh, soft focus`;

const COLOR_ACCENT_SUFFIX = `used sparingly on small props as a graphic highlight (not as a full background wash)`;

const PRESET_CARDS = [
  { name: "Red Tape", color: "deep red", subject: "rolls of red bureaucratic tape binding documents, frustrated office worker, filing cabinet" },
  { name: "Form 27-B/6", color: "", subject: "towering stack of identical government forms, rubber stamp, desk lamp casting hard shadows" },
  { name: "The Supervisor", color: "mustard yellow", subject: "stern middle manager in 1970s suit, clipboard, pointing finger, corner office" },
  { name: "Denied", color: "crimson red", subject: "large rubber stamp reading DENIED, ink splatter, crumpled paper, dejected clerk" },
  { name: "Budget Cut", color: "olive green", subject: "scissors cutting through stacked dollar bills, accountant with visor, ledger book" },
];

export default function PromptBuilder() {
  const [cardName, setCardName] = useState("");
  const [colorAccent, setColorAccent] = useState("");
  const [subject, setSubject] = useState("");
  const [copied, setCopied] = useState(null);

  const buildPositive = () => {
    let parts = [HOUSE_STYLE_POSITIVE];
    if (colorAccent.trim()) {
      parts.push(`${colorAccent.trim()} accent color ${COLOR_ACCENT_SUFFIX}`);
    }
    if (subject.trim()) {
      parts.push(subject.trim());
    }
    return parts.join(", ");
  };

  const buildNegative = () => HOUSE_STYLE_NEGATIVE;

  const loadPreset = (preset) => {
    setCardName(preset.name);
    setColorAccent(preset.color);
    setSubject(preset.subject);
    setCopied(null);
  };

  const copyToClipboard = (text, label) => {
    navigator.clipboard.writeText(text);
    setCopied(label);
    setTimeout(() => setCopied(null), 2000);
  };

  const clearAll = () => {
    setCardName("");
    setColorAccent("");
    setSubject("");
    setCopied(null);
  };

  return (
    <div style={{
      minHeight: "100vh",
      background: "#1a1410",
      fontFamily: "'Courier New', Courier, monospace",
      color: "#d4c4a0",
      padding: "0",
    }}>
      {/* Header */}
      <div style={{
        background: "#0f0d0a",
        borderBottom: "3px solid #8b6914",
        padding: "20px 32px",
        display: "flex",
        alignItems: "baseline",
        gap: "16px",
      }}>
        <div style={{
          fontSize: "11px",
          letterSpacing: "0.2em",
          color: "#8b6914",
          textTransform: "uppercase",
        }}>BUREAU OF CARD AFFAIRS</div>
        <div style={{
          fontSize: "20px",
          fontWeight: "bold",
          color: "#e8d5a3",
          letterSpacing: "0.05em",
        }}>ART PROMPT GENERATOR</div>
        <div style={{
          fontSize: "11px",
          letterSpacing: "0.15em",
          color: "#5a4a2a",
          marginLeft: "auto",
        }}>FORM GP-77 / COMFYUI EDITION</div>
      </div>

      <div style={{ maxWidth: "900px", margin: "0 auto", padding: "32px 24px" }}>

        {/* Stamp decoration */}
        <div style={{
          border: "3px solid #5a3a1a",
          borderRadius: "4px",
          padding: "24px",
          marginBottom: "28px",
          position: "relative",
          background: "#160f08",
        }}>
          <div style={{
            position: "absolute", top: "-11px", left: "20px",
            background: "#160f08", padding: "0 8px",
            fontSize: "10px", letterSpacing: "0.2em",
            color: "#8b6914", textTransform: "uppercase",
          }}>§ HOUSE STYLE — LOCKED</div>

          <div style={{ marginBottom: "14px" }}>
            <div style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#6b5030", marginBottom: "6px" }}>POSITIVE BASE</div>
            <div style={{
              background: "#0a0805",
              border: "1px solid #2a1f0f",
              borderRadius: "2px",
              padding: "10px 12px",
              fontSize: "12px",
              lineHeight: "1.6",
              color: "#a08050",
              wordBreak: "break-word",
            }}>{HOUSE_STYLE_POSITIVE}</div>
          </div>

          <div>
            <div style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#6b5030", marginBottom: "6px" }}>NEGATIVE BASE</div>
            <div style={{
              background: "#0a0805",
              border: "1px solid #2a1f0f",
              borderRadius: "2px",
              padding: "10px 12px",
              fontSize: "12px",
              lineHeight: "1.6",
              color: "#7a5040",
              wordBreak: "break-word",
            }}>{HOUSE_STYLE_NEGATIVE}</div>
          </div>
        </div>

        {/* Preset Cards */}
        <div style={{ marginBottom: "28px" }}>
          <div style={{ fontSize: "10px", letterSpacing: "0.2em", color: "#6b5030", marginBottom: "10px", textTransform: "uppercase" }}>
            § Load Example Card
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: "8px" }}>
            {PRESET_CARDS.map((p) => (
              <button
                key={p.name}
                onClick={() => loadPreset(p)}
                style={{
                  background: "transparent",
                  border: "1px solid #4a3520",
                  borderRadius: "2px",
                  color: "#a08050",
                  padding: "6px 14px",
                  fontSize: "11px",
                  letterSpacing: "0.1em",
                  cursor: "pointer",
                  fontFamily: "'Courier New', monospace",
                  transition: "all 0.15s",
                }}
                onMouseEnter={e => { e.target.style.borderColor = "#8b6914"; e.target.style.color = "#e8d5a3"; }}
                onMouseLeave={e => { e.target.style.borderColor = "#4a3520"; e.target.style.color = "#a08050"; }}
              >
                {p.name}
              </button>
            ))}
          </div>
        </div>

        {/* Card Input Form */}
        <div style={{
          border: "2px solid #4a3520",
          borderRadius: "4px",
          padding: "24px",
          marginBottom: "28px",
          background: "#120d08",
        }}>
          <div style={{
            fontSize: "10px", letterSpacing: "0.2em", color: "#8b6914",
            marginBottom: "20px", textTransform: "uppercase",
          }}>§ Card Specification</div>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px", marginBottom: "16px" }}>
            <div>
              <label style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#6b5030", display: "block", marginBottom: "6px" }}>
                CARD NAME (optional)
              </label>
              <input
                value={cardName}
                onChange={e => setCardName(e.target.value)}
                placeholder="e.g. Red Tape"
                style={{
                  width: "100%", boxSizing: "border-box",
                  background: "#0a0805", border: "1px solid #3a2a15",
                  borderRadius: "2px", color: "#e8d5a3",
                  padding: "8px 10px", fontSize: "13px",
                  fontFamily: "'Courier New', monospace",
                  outline: "none",
                }}
              />
            </div>
            <div>
              <label style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#6b5030", display: "block", marginBottom: "6px" }}>
                COLOR ACCENT (optional)
              </label>
              <input
                value={colorAccent}
                onChange={e => setColorAccent(e.target.value)}
                placeholder="e.g. deep red, mustard yellow"
                style={{
                  width: "100%", boxSizing: "border-box",
                  background: "#0a0805", border: "1px solid #3a2a15",
                  borderRadius: "2px", color: "#e8d5a3",
                  padding: "8px 10px", fontSize: "13px",
                  fontFamily: "'Courier New', monospace",
                  outline: "none",
                }}
              />
            </div>
          </div>

          <div>
            <label style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#6b5030", display: "block", marginBottom: "6px" }}>
              CARD SUBJECT / SCENE DESCRIPTION
            </label>
            <textarea
              value={subject}
              onChange={e => setSubject(e.target.value)}
              placeholder="e.g. rolls of red bureaucratic tape binding documents, frustrated office worker, filing cabinet"
              rows={3}
              style={{
                width: "100%", boxSizing: "border-box",
                background: "#0a0805", border: "1px solid #3a2a15",
                borderRadius: "2px", color: "#e8d5a3",
                padding: "8px 10px", fontSize: "13px",
                fontFamily: "'Courier New', monospace",
                outline: "none", resize: "vertical",
              }}
            />
          </div>

          <div style={{ marginTop: "12px", display: "flex", justifyContent: "flex-end" }}>
            <button onClick={clearAll} style={{
              background: "transparent", border: "1px solid #3a2a15",
              color: "#6b5030", padding: "6px 14px", fontSize: "11px",
              letterSpacing: "0.1em", cursor: "pointer",
              fontFamily: "'Courier New', monospace", borderRadius: "2px",
            }}>CLEAR FORM</button>
          </div>
        </div>

        {/* Output */}
        <div style={{
          border: "2px solid #8b6914",
          borderRadius: "4px",
          padding: "24px",
          background: "#0f0a05",
        }}>
          <div style={{
            fontSize: "10px", letterSpacing: "0.2em", color: "#8b6914",
            marginBottom: "20px", textTransform: "uppercase",
          }}>§ Generated Prompts {cardName && `— ${cardName.toUpperCase()}`}</div>

          {/* Positive */}
          <div style={{ marginBottom: "16px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
              <div style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#6b8a30" }}>POSITIVE PROMPT</div>
              <button
                onClick={() => copyToClipboard(buildPositive(), "positive")}
                style={{
                  background: copied === "positive" ? "#2a4010" : "transparent",
                  border: `1px solid ${copied === "positive" ? "#6b8a30" : "#3a5020"}`,
                  color: copied === "positive" ? "#a0c050" : "#5a7030",
                  padding: "3px 10px", fontSize: "10px",
                  letterSpacing: "0.1em", cursor: "pointer",
                  fontFamily: "'Courier New', monospace", borderRadius: "2px",
                  transition: "all 0.15s",
                }}
              >
                {copied === "positive" ? "✓ COPIED" : "COPY"}
              </button>
            </div>
            <div style={{
              background: "#080602", border: "1px solid #2a3a10",
              borderRadius: "2px", padding: "12px",
              fontSize: "12px", lineHeight: "1.7",
              color: "#b0d060", wordBreak: "break-word",
              minHeight: "60px",
            }}>
              {buildPositive()}
            </div>
          </div>

          {/* Negative */}
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
              <div style={{ fontSize: "10px", letterSpacing: "0.15em", color: "#8a4030" }}>NEGATIVE PROMPT</div>
              <button
                onClick={() => copyToClipboard(buildNegative(), "negative")}
                style={{
                  background: copied === "negative" ? "#3a1008" : "transparent",
                  border: `1px solid ${copied === "negative" ? "#8a4030" : "#5a2010"}`,
                  color: copied === "negative" ? "#c05030" : "#7a3020",
                  padding: "3px 10px", fontSize: "10px",
                  letterSpacing: "0.1em", cursor: "pointer",
                  fontFamily: "'Courier New', monospace", borderRadius: "2px",
                  transition: "all 0.15s",
                }}
              >
                {copied === "negative" ? "✓ COPIED" : "COPY"}
              </button>
            </div>
            <div style={{
              background: "#080602", border: "1px solid #3a1008",
              borderRadius: "2px", padding: "12px",
              fontSize: "12px", lineHeight: "1.7",
              color: "#c07060", wordBreak: "break-word",
            }}>
              {buildNegative()}
            </div>
          </div>
        </div>

        {/* Footer */}
        <div style={{
          marginTop: "24px", textAlign: "center",
          fontSize: "10px", letterSpacing: "0.15em",
          color: "#3a2a10",
        }}>
          BUREAU OF CARD AFFAIRS · FORM GP-77 · ALL PROMPTS SUBJECT TO REVISION · DO NOT STAPLE
        </div>
      </div>
    </div>
  );
}


