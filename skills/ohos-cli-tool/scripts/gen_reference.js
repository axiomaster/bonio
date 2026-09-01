
const fs = require("fs");
const path = require("path");
const dir = process.argv[2];
const files = fs.readdirSync(dir).filter(f => f.endsWith(".json")).sort();
const out = [];
for (const f of files) {
  const c = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
  out.push("## " + c.name);
  out.push(c.description || "");
  if (c.requirePermissions?.length) out.push("Permissions: " + c.requirePermissions.join(", "));
  if (c.hasSubCommand) {
    for (const [sub, s] of Object.entries(c.subcommands || {})) {
      if (sub === "--help") continue;
      out.push("### " + sub);
      if (s.description) out.push(s.description);
      const props = s.inputSchema?.properties || {};
      const req = s.inputSchema?.required || [];
      for (const [k, v] of Object.entries(props)) {
        const t = v.type || "";
        const en = v.enum ? " enum:[" + v.enum.join("|") + "]" : "";
        const dv = v.default !== undefined ? " default:" + JSON.stringify(v.default) : "";
        const rq = req.includes(k) ? " REQUIRED" : "";
        out.push("- --" + k + " <" + t + ">" + rq + en + dv + (v.description ? " — " + v.description : ""));
      }
    }
  } else {
    const props = c.inputSchema?.properties || {};
    const req = c.inputSchema?.required || [];
    for (const [k, v] of Object.entries(props)) {
      const t = v.type || "";
      const rq = req.includes(k) ? " REQUIRED" : "";
      out.push("- --" + k + " <" + t + ">" + rq + (v.description ? " — " + v.description : ""));
    }
  }
  out.push("");
}
fs.writeFileSync(path.join(dir, "..", "REFERENCE.md"), out.join("\n"));
console.log("written " + out.length + " lines");
