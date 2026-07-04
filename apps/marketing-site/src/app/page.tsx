// Placeholder landing page. FEAT-036's cinematic build-out (3D hero,
// house-assembly scroll animation, per website-design-patterns.md) ships in
// Phase 5, by a dedicated sequential section-by-section dispatch -- not
// parallel subagents, since it shares a single WebGL render loop/scene.
export default function HomePage() {
  return (
    <main style={{ padding: "2rem" }}>
      <h1>De-Duke</h1>
      <p>Verified property. Real conversations. Deals that close.</p>
      <p>
        Full cinematic landing experience (FEAT-036) ships in Phase 5. Legal & Policy pages
        (FEAT-037) are live now, ahead of the full site, per roadmap.md.
      </p>
    </main>
  );
}
