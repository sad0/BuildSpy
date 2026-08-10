// BuildSpy -- "Copy build for BuildSpy" bookmarklet for Darkmoon Logs armory.
//
// WoW 3.3.5 addons cannot make web requests, so BuildSpy cannot read an armory
// URL from inside the game. This runs in YOUR browser instead. The armory API
// blocks cross-site requests (CORS), so the bookmarklet must run WHILE you are
// on darkmoon.ascensionlogs.gg -- but you no longer need each player's page:
// click it anywhere on the site and it PROMPTS for a player name or URL, then
// copies a BuildSpy text export to your clipboard. Paste it into BuildSpy's
// Import (the build appears under that character name).
//
// Tip: if your bookmarks bar is hidden while browsing, Ctrl+Shift+B toggles it
// (Chrome/Edge/Firefox), or open the bookmark from the bookmarks menu.
//
// The minified one-line version to save as a bookmark is armory-bookmarklet.txt.
// Keep the two in sync if you edit.

(async function () {
    try {
        var host = location.host || "";
        if (host.indexOf("ascensionlogs.gg") === -1) {
            if (confirm("BuildSpy: the armory blocks cross-site requests, so this must run on darkmoon.ascensionlogs.gg. Open it now?")) {
                location.href = "https://darkmoon.ascensionlogs.gg/";
            }
            return;
        }
        var origin = location.origin;
        var current = decodeURIComponent(
            (location.pathname.split("/").filter(Boolean).pop() || "")
        );
        var input = window.prompt("Player name or armory URL:", current || "");
        if (!input) return;
        input = input.trim();
        var m = input.match(/armory\/([^\/?#]+)/i);
        var name = m ? decodeURIComponent(m[1]) : input;

        var byName = await (await fetch(
            origin + "/api/armory/by-name/" + encodeURIComponent(name)
        )).json();
        var charId = byName && byName.character && byName.character.id;
        if (!charId) { alert("No armory data for " + name + "."); return; }

        var j = await (await fetch(origin + "/api/armory/character/" + charId)).json();
        var ci = j.ci_resolved || {};
        var sp = ci.specialization || {};

        var pathMap = {
            strength: "Path of Strength", agility: "Path of Agility",
            intellect: "Path of Intelligence", spirit: "Path of Healing",
            healing: "Path of Healing", duality: "Path of Duality"
        };
        var token = (ci.primary_stat && ci.primary_stat.token) || "";
        var pathName = pathMap[token] || null;

        var trees = (sp.talents && sp.talents.trees) || {};
        var abilities = [], talents = [];
        Object.keys(trees).forEach(function (slug) {
            (trees[slug].talents || []).forEach(function (n) {
                if (!n.name) return;
                (slug === "talents" ? talents : abilities).push(n.name);
            });
        });

        var out = [];
        var player = (ci.player && ci.player.name) || name;
        var date = new Date().toISOString().slice(0, 16).replace("T", " ");
        out.push("[BuildSpy] " + player + ", spec 1, armory, " + date);
        if (pathName) out.push(pathName);
        out.push("==Spells==");
        abilities.forEach(function (x) { out.push(x); });
        out.push("==Talents==");
        talents.forEach(function (x) { out.push(x); });

        var gear = ci.gear || {};
        var slots = Object.keys(gear).map(Number).sort(function (a, b) { return a - b; });
        if (slots.length) {
            out.push("==Gear==");
            slots.forEach(function (s) {
                var g = gear[s];
                var id = g.item_id, ench = g.enchant || 0;
                var nm = (g.resolved_item && g.resolved_item.name) || "";
                if (id) out.push("s" + s + " " + id + ":" + ench + (nm ? "  " + nm : ""));
            });
        }

        var text = out.join("\n");
        var done = function () {
            alert("BuildSpy: copied " + player + " (" + abilities.length
                + " spells, " + talents.length + " talents). Paste into BuildSpy Import.");
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done, function () { window.prompt("Copy the build:", text); });
        } else {
            window.prompt("Copy the build:", text);
        }
    } catch (e) {
        alert("BuildSpy armory export failed: " + e);
    }
})();
