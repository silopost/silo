#!/usr/bin/env node
// Generuje korpus seed/mail/*.eml (CRLF) oraz seed/mail/manifest.yaml.
// Uzycie: node scripts/gen-seed.mjs   (wynik jest commitowany; generator zostaje dla powtarzalnosci)
// Dane fikcyjne: domeny silo.test i example.com. Daty: listopad 2026.
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "seed", "mail");
mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) if (f.endsWith(".eml") || f === "manifest.yaml") rmSync(join(OUT, f));

// --- kodowania jednobajtowe (tylko polskie litery; reszta ASCII) ---
const TABLES = {
  "iso-8859-2": { ą: 0xb1, ć: 0xe6, ę: 0xea, ł: 0xb3, ń: 0xf1, ó: 0xf3, ś: 0xb6, ź: 0xbc, ż: 0xbf, Ą: 0xa1, Ć: 0xc6, Ę: 0xca, Ł: 0xa3, Ń: 0xd1, Ó: 0xd3, Ś: 0xa6, Ź: 0xac, Ż: 0xaf },
  "windows-1250": { ą: 0xb9, ć: 0xe6, ę: 0xea, ł: 0xb3, ń: 0xf1, ó: 0xf3, ś: 0x9c, ź: 0x9f, ż: 0xbf, Ą: 0xa5, Ć: 0xc6, Ę: 0xca, Ł: 0xa3, Ń: 0xd1, Ó: 0xd3, Ś: 0x8c, Ź: 0x8f, Ż: 0xaf },
};
function toBytes(str, charset) {
  if (charset === "utf-8") return Buffer.from(str, "utf8");
  const t = TABLES[charset];
  return Buffer.from(
    Array.from(str).map((ch) => {
      const c = ch.codePointAt(0);
      if (c < 0x80) return c;
      if (t[ch] === undefined) throw new Error(`brak znaku ${ch} w ${charset}`);
      return t[ch];
    }),
  );
}
const b64 = (buf) => buf.toString("base64").match(/.{1,76}/g)?.join("\r\n") ?? "";
function qp(buf) {
  let out = "";
  let line = "";
  const push = (s) => {
    if (line.length + s.length > 75) {
      out += line + "=\r\n";
      line = "";
    }
    line += s;
  };
  for (let i = 0; i < buf.length; i++) {
    const b = buf[i];
    if (b === 0x0a) {
      out += line + "\r\n";
      line = "";
      continue;
    }
    if (b === 0x0d) continue;
    const trailing = buf[i + 1] === 0x0a || i === buf.length - 1;
    if ((b === 0x20 || b === 0x09) && !trailing) push(String.fromCharCode(b));
    else if (b >= 33 && b <= 126 && b !== 61) push(String.fromCharCode(b));
    else push("=" + b.toString(16).toUpperCase().padStart(2, "0"));
  }
  return out + line;
}
const isAscii = (s) => /^[\x20-\x7e]*$/.test(s);
// Encoded-word (B); dlugie wartosci dzielone na slowa rozdzielone spacja (zlozenie linii robi fold()).
function encWord(str, charset = "utf-8") {
  if (isAscii(str)) return str;
  const cs = Array.from(str);
  const chunks = [];
  for (let i = 0; i < cs.length; i += 18) chunks.push(cs.slice(i, i + 18).join(""));
  return chunks.map((c) => `=?${charset}?B?${toBytes(c, charset).toString("base64")}?=`).join(" ");
}
function fold(name, value) {
  let out = `${name}:`;
  let len = out.length;
  for (const w of value.split(" ")) {
    if (len + 1 + w.length > 76 && len > name.length + 1) {
      out += "\r\n";
      len = 0;
    }
    out += " " + w;
    len += 1 + w.length;
  }
  return out;
}
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function dates(local) {
  // "2026-11-02 09:15" w CET (+0100)
  const [d, t] = local.split(" ");
  const [y, mo, da] = d.split("-").map(Number);
  const [h, mi] = t.split(":").map(Number);
  const dow = DAYS[new Date(Date.UTC(y, mo - 1, da)).getUTCDay()];
  const p = (n) => String(n).padStart(2, "0");
  return {
    rfc: `${dow}, ${p(da)} ${MONS[mo - 1]} ${y} ${p(h)}:${p(mi)}:00 +0100`,
    imap: `${p(da)}-${MONS[mo - 1]}-${y} ${p(h)}:${p(mi)}:00 +0100`,
  };
}

// --- ludzie ---
const P = {
  anna: ["Anna Kowalska", "anna.kowalska@example.com"],
  piotr: ["Piotr Nowak", "piotr.nowak@example.com"],
  marta: ["Marta Wiśniewska", "marta.wisniewska@example.com"],
  jan: ["Jan Dąbrowski", "jan.dabrowski@silo.test"],
  ewa: ["Ewa Zielińska", "ewa.zielinska@example.com"],
  tomek: ["Tomasz Lewandowski", "t.lewandowski@example.com"],
  dev1: ["Dev One", "dev1@silo.test"],
  dev2: ["Dev Two", "dev2@silo.test"],
  dev3: ["Dev Three", "dev3@silo.test"],
  shop: ["Sklep Przykład", "billing@shop.example.com"],
  news: ["Biuletyn Silo Test", "news@news.example.com"],
  ci: ["CI Silo", "ci@build.example.com"],
};
const addr = (k, cs = "utf-8") => `${encWord(P[k][0], cs)} <${P[k][1]}>`;

// --- definicje wiadomosci (kolejnosc = numeracja plikow = kolejnosc dostarczania) ---
const M = [];
const msg = (o) => {
  M.push({ folder: "INBOX", via: "smtp", cs: "utf-8", cte: "qp", flags: "", ...o });
};
const L = (...l) => l.join("\n");

// T1: plan sprintu (INBOX + Sent)
msg({ key: "t1a", from: "anna", to: ["dev1"], subj: "Plan sprintu 47", date: "2026-11-02 09:15",
  body: L("Cześć,", "", "proponuję taki zakres sprintu 47:", "- migracje bazy danych,", "- synchronizacja skrzynek,", "- widok wątków.", "", "Daj znać, co o tym myślisz.", "Anna") });
msg({ key: "t1s1", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["anna"], subj: "Re: Plan sprintu 47", date: "2026-11-02 09:50", reply: "t1a",
  body: L("Cześć Anno,", "", "zakres wygląda dobrze, ale widok wątków przeniósłbym na sprint 48.", "", "Dev One") });
msg({ key: "t1b", from: "piotr", to: ["dev1"], cc: ["anna"], subj: "Re: Plan sprintu 47", date: "2026-11-02 10:30", reply: "t1s1",
  body: L("Zgadzam się z Devem – wątki później.", "Mogę wziąć synchronizację.", "", "Piotr") });
msg({ key: "t1s2", folder: "Sent", via: "append", flags: "\\Seen \\Answered", from: "dev1", to: ["piotr"], cc: ["anna"], subj: "Re: Plan sprintu 47", date: "2026-11-02 11:05", reply: "t1b",
  body: L("Świetnie, przypisuję synchronizację do Piotra.", "", "Dev One") });
msg({ key: "t1c", from: "anna", to: ["dev1", "piotr"], subj: "Re: Plan sprintu 47", date: "2026-11-03 08:40", reply: "t1s2", refsMode: "in-reply-to",
  body: L("Zatwierdzone, sprint startuje w środę.", "", "Anna") });
msg({ key: "t1n", via: "append", flags: "\\Flagged Praca", from: "anna", to: ["dev1"], subj: "Re: Plan sprintu 47", date: "2026-11-03 09:05", reply: "t1c", noMid: true,
  body: L("PS. Wiadomość bez Message-ID (dodana przez APPEND), ale z In-Reply-To.", "", "Anna") });

// T2: oferta, zmiana tematu w watku, zalacznik
msg({ key: "t2a", from: "marta", to: ["dev1"], subj: "Zapytanie o ofertę serwerów", date: "2026-11-02 12:00", cte: "base64",
  body: L("Dzień dobry,", "", "prosimy o wycenę 3 serwerów do obsługi poczty (16 GB RAM, 2 TB SSD).", "", "Pozdrawiam,", "Marta Wiśniewska") });
msg({ key: "t2s", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["marta"], subj: "Re: Zapytanie o ofertę serwerów", date: "2026-11-02 14:10", reply: "t2a",
  body: L("Dzień dobry,", "", "wycenę prześlemy jutro rano.", "", "Dev One") });
msg({ key: "t2b", from: "marta", to: ["dev1"], subj: "Oferta serwerów – wersja 2 (zmiana zakresu)", date: "2026-11-03 09:00", reply: "t2s",
  att: [{ name: "oferta-v2.pdf", type: "application/pdf", kind: "pdf" }],
  body: L("W załączniku poprawiona oferta po zmianie zakresu.", "Temat wątku zmieniony celowo.", "", "Marta") });
msg({ key: "t2c", from: "marta", to: ["dev1"], subj: "Re: Oferta serwerów – wersja 2 (zmiana zakresu)", date: "2026-11-03 15:20", reply: "t2b",
  body: L("Czy możemy omówić ofertę jutro o 10:00?", "", "Marta") });

// T3: out-of-order (odpowiedzi trafiaja przed rodzicem)
msg({ key: "t3c", from: "jan", to: ["dev2"], cc: ["dev1"], subj: "Re: Release 2.3 checklist", date: "2026-11-03 09:45", reply: "t3b",
  body: L("Dzięki, punkt 4 dopiszę dziś.", "", "Jan") });
msg({ key: "t3b", from: "dev2", to: ["jan"], cc: ["dev1"], subj: "Re: Release 2.3 checklist", date: "2026-11-03 09:20", reply: "t3a",
  body: L("Dodałem punkty 3 i 4 (testy migracji, changelog).", "", "Dev Two") });
msg({ key: "t3a", from: "jan", to: ["dev1", "dev2", "dev3"], subj: "Release 2.3 checklist", date: "2026-11-03 09:00",
  body: L("Lista przed wydaniem 2.3:", "1. zamrożenie gałęzi", "2. smoke testy", "", "Uzupełnijcie, proszę.", "", "Jan") });
msg({ key: "t3d", from: "dev3", to: ["jan"], cc: ["dev1"], subj: "Re: Release 2.3 checklist", date: "2026-11-03 10:10", reply: "t3a",
  body: L("Dopisuję punkt 5: aktualizacja dokumentacji.", "", "Dev Three") });
msg({ key: "t3s1", folder: "Sent", via: "append", flags: "\\Seen \\Answered", from: "dev1", to: ["jan"], cc: ["dev2"], subj: "Re: Release 2.3 checklist", date: "2026-11-03 10:30", reply: "t3c",
  body: L("Potwierdzam, lista kompletna.", "", "Dev One") });
msg({ key: "t3s2", folder: "Sent", via: "append", flags: "\\Seen $Forwarded", from: "dev1", to: ["dev3"], subj: "Re: Release 2.3 checklist", date: "2026-11-03 10:35", reply: "t3d",
  body: L("Dokumentacją zajmę się ja.", "", "Dev One") });

// T4: HTML
const html = (title, lines) => `<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>${title}</title></head>\n<body style="font-family: sans-serif">\n<h2>${title}</h2>\n${lines.map((l) => `<p>${l}</p>`).join("\n")}\n</body></html>`;
msg({ key: "t4a", from: "ewa", to: ["dev1"], subj: "Spotkanie w czwartek", date: "2026-11-03 13:00",
  body: L("Spotkanie zespołu w czwartek o 11:00, sala 2.", "Agenda w wersji HTML."),
  html: html("Spotkanie w czwartek", ["Spotkanie zespołu w <b>czwartek o 11:00</b>, sala 2.", "Agenda: <ul><li>status</li><li>plany</li></ul>"]) });
msg({ key: "t4b", from: "tomek", to: ["ewa"], cc: ["dev1"], subj: "Re: Spotkanie w czwartek", date: "2026-11-03 13:30", reply: "t4a",
  html: html("Re: Spotkanie w czwartek", ["Będę, ale mogę wyjść o 12:00.", "<i>Tomasz</i>"]) });
msg({ key: "t4s", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["ewa"], cc: ["tomek"], subj: "Re: Spotkanie w czwartek", date: "2026-11-03 14:00", reply: "t4b",
  body: L("Będę na miejscu.", "", "Dev One"), html: html("Re: Spotkanie w czwartek", ["Będę na miejscu.", "Dev One"]) });

// T5: dluzszy watek z rozgalezieniem (References i tylko In-Reply-To)
const t5 = "Awaria wdrożenia na stagingu";
msg({ key: "t5a", from: "jan", to: ["dev1", "dev2", "dev3"], subj: t5, date: "2026-11-04 07:30",
  body: L("Wdrożenie na stagingu zakończyło się błędem migracji 000012.", "Ktoś patrzy?", "", "Jan") });
msg({ key: "t5b", from: "dev2", to: ["jan"], cc: ["dev1", "dev3"], subj: `Re: ${t5}`, date: "2026-11-04 07:42", reply: "t5a",
  body: L("Widzę, brakuje indeksu przed ALTER TABLE. Sprawdzam.", "", "Dev Two") });
msg({ key: "t5c", from: "piotr", to: ["dev2"], cc: ["jan", "dev1"], subj: `Re: ${t5}`, date: "2026-11-04 07:55", reply: "t5b", refsMode: "in-reply-to",
  body: L("Ta sama migracja padła u mnie lokalnie tydzień temu.", "", "Piotr") });
msg({ key: "t5s1", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["piotr", "dev2"], subj: `Re: ${t5}`, date: "2026-11-04 08:05", reply: "t5c",
  body: L("Piotr, wrzuć proszę logi, Dev Two poprawia migrację.", "", "Dev One") });
msg({ key: "t5d", from: "jan", to: ["dev1"], subj: `Re: ${t5}`, date: "2026-11-04 08:20", reply: "t5s1",
  body: L("Logi w załączniku do ticketu. Czekam na poprawkę.", "", "Jan") });
msg({ key: "t5e", from: "dev3", to: ["jan"], cc: ["dev1"], subj: `Re: ${t5}`, date: "2026-11-04 08:25", reply: "t5a",
  body: L("Osobna gałąź rozmowy: mogę zrobić rollback stagingu.", "", "Dev Three") });
msg({ key: "t5s2", folder: "Sent", via: "append", flags: "\\Seen \\Answered Praca", from: "dev1", to: ["dev3"], subj: `Re: ${t5}`, date: "2026-11-04 08:30", reply: "t5e",
  body: L("Rollback tak, ale po poprawce migracji.", "", "Dev One") });
msg({ key: "t5f", from: "jan", to: ["dev1", "dev2"], subj: `Re: Re: ${t5}`, date: "2026-11-04 09:10", reply: "t5d",
  body: L("Poprawka wdrożona, staging działa.", "", "Jan") });
msg({ key: "t5s3", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["jan"], cc: ["dev2", "dev3"], subj: `Re: ${t5}`, date: "2026-11-04 09:20", reply: "t5f",
  body: L("Dziękuję wszystkim, zamykam temat.", "", "Dev One") });

// T6: ISO-8859-2 i Windows-1250
msg({ key: "t6a", from: "ewa", to: ["dev1"], subj: "Zażółć gęślą jaźń – test kodowań".replace("–", "-"), date: "2026-11-02 16:00", cs: "iso-8859-2", cte: "qp",
  body: L("Pchnąć w tę łódź jeża lub ośm skrzyń fig.", "Wiadomość w ISO-8859-2, treść Quoted-Printable.", "", "Ewa") });
msg({ key: "t6b", from: "tomek", to: ["ewa"], cc: ["dev1"], subj: "Re: Zażółć gęślą jaźń - test kodowań", date: "2026-11-02 16:20", cs: "iso-8859-2", cte: "base64", reply: "t6a",
  body: L("Zażółć gęślą jaźń - odpowiedź w ISO-8859-2, treść Base64.", "", "Tomasz") });
msg({ key: "t6s", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["ewa", "tomek"], subj: "Re: Zażółć gęślą jaźń - test kodowań", date: "2026-11-02 16:45", reply: "t6b",
  body: L("Dzięki, wszystko czytelne po mojej stronie (UTF-8).", "", "Dev One") });
msg({ key: "t6c", from: "jan", to: ["dev1"], subj: "Łódź - harmonogram dostaw", date: "2026-11-02 17:00", cs: "windows-1250", cte: "qp",
  body: L("Harmonogram dostaw do Łodzi: poniedziałek, środa, piątek.", "Kodowanie Windows-1250, Quoted-Printable.", "", "Jan") });
msg({ key: "t6d", from: "marta", to: ["jan"], cc: ["dev1"], subj: "Re: Łódź - harmonogram dostaw", date: "2026-11-02 17:30", cs: "windows-1250", cte: "base64", reply: "t6c",
  body: L("Czy piątek można przesunąć na sobotę? Pozdrawiam, Marta Wiśniewska", "Windows-1250, Base64.") });

// wiadomosc do siebie (kopia w INBOX i Sent, ten sam Message-ID)
msg({ key: "self", from: "dev1", to: ["dev1"], subj: "Notatka dla siebie: zadania na jutro", date: "2026-11-03 22:00",
  body: L("1. Przejrzeć PR-y", "2. Zaktualizować dokumentację", "3. Odpisać Marcie") });
msg({ key: "selfs", folder: "Sent", via: "append", flags: "\\Seen", from: "dev1", to: ["dev1"], subj: "Notatka dla siebie: zadania na jutro", date: "2026-11-03 22:00", sameAs: "self",
  body: L("1. Przejrzeć PR-y", "2. Zaktualizować dokumentację", "3. Odpisać Marcie") });

// maile od innych kont dev
msg({ key: "lunch", from: "dev2", to: ["dev1"], subj: "Lunch?", date: "2026-11-04 11:30", cte: "7bit", body: L("Idziemy na lunch o 12:30?", "Dev Two") });
msg({ key: "review", from: "dev3", to: ["dev1"], cc: ["dev2"], subj: "Prośba o review: PR #214", date: "2026-11-04 10:00",
  body: L("Mógłbyś rzucić okiem na PR #214 (obsługa QRESYNC)?", "", "Dev Three") });

// newslettery (HTML + tekst, QP)
for (let i = 0; i < 6; i++) {
  const n = 38 + i;
  const day = 1 + Math.floor(i / 2);
  const hh = i % 2 ? "18:00" : "07:00";
  msg({ key: `news${n}`, from: "news", to: ["dev1"], subj: `Biuletyn Silo Test #${n}: nowości tygodnia`, date: `2026-11-0${day} ${hh}`,
    body: L(`Biuletyn #${n}`, "Najnowsze wpisy: wydajność IMAP, wątki, skróty klawiszowe.", "Wypisz się: https://news.example.com/unsubscribe"),
    html: html(`Biuletyn #${n}`, [`Najnowsze wpisy: <a href="https://news.example.com/n/${n}">wydajność IMAP</a>, wątki, skróty klawiszowe.`, '<small>Wypisz się: <a href="https://news.example.com/unsubscribe">tutaj</a></small>']) });
}

// faktury z zalacznikami
for (const [i, kind] of [[153, "pdf"], [154, "pdf"], [155, "csv"]]) {
  msg({ key: `inv${i}`, from: "shop", to: ["dev1"], subj: `Faktura FV/2026/11/0${i}`, date: `2026-11-0${i - 152} 08:00`,
    att: [{ name: kind === "pdf" ? `FV-2026-11-0${i}.pdf` : `zestawienie-0${i}.csv`, type: kind === "pdf" ? "application/pdf" : "text/csv", kind }],
    body: L("Dzień dobry,", "w załączniku faktura za zamówienie.", "", "Sklep Przykład") });
}

// inline obrazy
for (const [k, subj, who, day] of [["img1", "Logo nowego produktu", "ewa", "2026-11-03 11:00"], ["img2", "Zdjęcie ze spotkania", "tomek", "2026-11-04 12:15"]]) {
  msg({ key: k, from: who, to: ["dev1"], subj, date: day, inline: true,
    body: L(`${subj} (obraz osadzony w HTML).`),
    html: `<html><body><p>${subj}:</p><p><img src="cid:${k}@silo.test" alt="obraz" width="1" height="1"></p></body></html>` });
}

// dodatkowe pojedyncze
msg({ key: "urlop", from: "marta", to: ["dev1"], subj: "Przypomnienie: wniosek urlopowy", date: "2026-11-04 13:00", body: L("Przypominam o złożeniu wniosku urlopowego do piątku.") });
msg({ key: "webinar", from: "news", to: ["dev1"], subj: "Zaproszenie na webinar: IMAP w praktyce", date: "2026-11-04 14:00",
  body: L("Zapraszamy na webinar 12.11.2026, 18:00.", "Rejestracja: https://news.example.com/webinar") });

// powiadomienia CI (osobne wiadomosci, brak watkowania)
for (let i = 0; i < 16; i++) {
  const build = 1201 + i;
  const ok = i % 4 !== 3;
  const day = 3 + Math.floor(i / 8);
  const min = String((i % 8) * 7 + 5).padStart(2, "0");
  msg({ key: `ci${build}`, from: "ci", to: ["dev1"], subj: `[ci] build #${build} ${ok ? "passed" : "FAILED"}`, date: `2026-11-0${day} ${String(9 + (i % 8)).padStart(2, "0")}:${min}`, cte: "7bit",
    body: L(`Build #${build} on main: ${ok ? "passed" : "FAILED"}.`, `Duration: ${2 + (i % 5)}m ${10 + i}s`, `Details: https://ci.example.com/builds/${build}`) });
}

// dodatkowe wiadomosci wstrzykiwane APPEND do INBOX
msg({ key: "fwd", via: "append", flags: "\\Seen $Forwarded", from: "news", to: ["dev1"], subj: "Biuletyn Silo Test #37: archiwum", date: "2026-10-30 07:00",
  body: L("Archiwalne wydanie biuletynu #37 (dodane przez APPEND z flagą $Forwarded).") });
msg({ key: "nomid", via: "append", noMid: true, flags: "\\Flagged", from: "tomek", to: ["dev1"], subj: "Zaproszenie bez identyfikatora", date: "2026-11-04 15:00",
  body: L("Ta wiadomość celowo nie ma nagłówka Message-ID.", "", "Tomasz") });

// --- budowa MIME ---
const mid = (m) => `<seed-${m.sameAs ?? m.key}@${P[m.from][1].split("@")[1]}>`;
const byKey = new Map();
M.forEach((m, i) => {
  m.n = String(i + 1).padStart(4, "0");
  byKey.set(m.key, m);
});
const refsOf = (m) => {
  const p = m.reply && byKey.get(m.reply);
  return p ? [...refsOf(p), mid(p)] : [];
};

const PDF = () => {
  const lines = ["%PDF-1.4", "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj"];
  for (let i = 0; i < 90; i++) lines.push(`% seed line ${i}: dummy content for attachment size, not a real PDF`);
  lines.push("%%EOF");
  return Buffer.from(lines.join("\n"));
};
const CSV = () => Buffer.from("lp;opis;kwota\n" + Array.from({ length: 60 }, (_, i) => `${i + 1};pozycja ${i + 1};${(10 + i * 1.5).toFixed(2)}`).join("\n") + "\n");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");

function textPart(text, cs, cte, subtype = "plain") {
  const bytes = toBytes(text, cs);
  const body = cte === "base64" ? b64(bytes) : cte === "qp" ? qp(bytes) : bytes.toString("latin1");
  return [`Content-Type: text/${subtype}; charset=${cs}`, `Content-Transfer-Encoding: ${cte === "qp" ? "quoted-printable" : cte}`, "", body].join("\r\n");
}
function build(m) {
  const cs = m.cs;
  if (m.cte === "7bit" && !isAscii((m.body ?? "").replace(/\n/g, ""))) m.cte = "qp";
  const h = [];
  h.push(fold("From", addr(m.from, cs)));
  h.push(fold("To", m.to.map((k) => addr(k, cs)).join(", ")));
  if (m.cc) h.push(fold("Cc", m.cc.map((k) => addr(k, cs)).join(", ")));
  h.push(fold("Subject", encWord(m.subj, cs)));
  h.push(`Date: ${dates(m.date).rfc}`);
  if (!m.noMid) h.push(`Message-ID: ${mid(m)}`);
  if (m.reply) {
    h.push(`In-Reply-To: ${mid(byKey.get(m.reply))}`);
    if (m.refsMode !== "in-reply-to") h.push(fold("References", refsOf(m).join(" ")));
  }
  h.push("MIME-Version: 1.0");
  h.push("X-Seed: silo-dev");
  const mk = (n) => `----=_seed_${m.n}_${n}`;
  let alt;
  if (m.html && m.inline) {
    const rel = [`Content-Type: multipart/related; boundary="${mk("r")}"`, "", `--${mk("r")}`, textPart(m.html, cs, m.cte, "html"),
      `--${mk("r")}`, 'Content-Type: image/png; name="obraz.png"', "Content-Transfer-Encoding: base64", `Content-ID: <${m.key}@silo.test>`, 'Content-Disposition: inline; filename="obraz.png"', "", b64(PNG), `--${mk("r")}--`].join("\r\n");
    alt = [`Content-Type: multipart/alternative; boundary="${mk("a")}"`, "", `--${mk("a")}`, textPart(m.body, cs, m.cte), `--${mk("a")}`, rel, `--${mk("a")}--`].join("\r\n");
  } else if (m.html && m.body) {
    alt = [`Content-Type: multipart/alternative; boundary="${mk("a")}"`, "", `--${mk("a")}`, textPart(m.body, cs, m.cte), `--${mk("a")}`, textPart(m.html, cs, m.cte, "html"), `--${mk("a")}--`].join("\r\n");
  } else if (m.html) {
    alt = textPart(m.html, cs, m.cte, "html");
  } else {
    alt = textPart(m.body, cs, m.cte);
  }
  let top = alt;
  if (m.att) {
    const parts = [`Content-Type: multipart/mixed; boundary="${mk("m")}"`, "", `--${mk("m")}`, alt];
    for (const a of m.att) {
      parts.push(`--${mk("m")}`, `Content-Type: ${a.type}; name="${a.name}"`, "Content-Transfer-Encoding: base64", `Content-Disposition: attachment; filename="${a.name}"`, "", b64(a.kind === "pdf" ? PDF() : CSV()));
    }
    parts.push(`--${mk("m")}--`);
    top = parts.join("\r\n");
  }
  return h.join("\r\n") + "\r\n" + top + "\r\n";
}

const slug = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/ł/g, "l").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
let yaml = "# Generowany przez scripts/gen-seed.mjs - nie edytuj recznie.\n# via: smtp   -> dostarczane przez SMTP (flagi i data ignorowane: ustawia serwer);\n# via: append -> IMAP APPEND do folderu z flagami i INTERNALDATE (scripts/seed-mail.sh --append).\nmessages:\n";
const stat = { inbox: 0, appendInbox: 0, sent: 0 };
for (const m of M) {
  const file = `${m.n}-${slug(m.subj)}.eml`;
  writeFileSync(join(OUT, file), build(m), "latin1");
  yaml += `  - file: ${file}\n    folder: ${m.folder}\n    via: ${m.via}\n    flags: "${m.flags.replace(/\\/g, "\\\\")}"\n    date: "${dates(m.date).imap}"\n`;
  if (m.folder === "Sent") stat.sent++;
  else if (m.via === "smtp") stat.inbox++;
  else stat.appendInbox++;
}
writeFileSync(join(OUT, "manifest.yaml"), yaml);
console.log(`${M.length} plikow: INBOX/smtp=${stat.inbox}, INBOX/append=${stat.appendInbox}, Sent/append=${stat.sent}`);
