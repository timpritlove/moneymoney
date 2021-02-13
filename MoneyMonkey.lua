--
-- Export von MoneyMoney Umsätzen zu direkt importierbaren Steuer-Buchungssätzen.
--
-- Dieses Skript ist getestet mit MonKey Office, sollte aber im Prinzip auch mit allen
-- anderen Buchhaltungsprogrammen funktionieren, die Buchungssätze als CSV-Datei
-- direkt importieren können (was vermutlich nahezu alle sind).
--
-- Das Skript liest eine zweite Lua-Datei ein, in der sich die eigentliche Konfiguration
-- befindet. Diese muss an die eigenen Bedürfnisse und Verhältnisse angepasst werden.
--
-- Erforderliche MoneyMoney-Version: 2.3.25

-- CSV Dateieinstellungen

local encoding     = "UTF-8"
local utf_bom      = false
local linebreak    = "\n"

-- Exportformat bei MoneyMoney anmelden

Exporter{version       = 1.5,
         options     = {
           { label="Umsätze müssen als erledigt markiert sein", name="checkedOnly", default=true }
         },
         format        = MM.localizeText("Buchungssätze"),
         fileExtension = "csv",
         reverseOrder  = true,
         description   = MM.localizeText("Export von MoneyMoney Umsätzen zu direkt importierbaren Steuer-Buchungssätzen.")}


-- Definition der Reihenfolge und Titel der zu exportierenden Buchungsfelder
-- Format: Key (Internes Feld), Titel (in der ersten Zeile der CSV-Datei)

Exportdatei = {
 { "Datum",          "Datum" },
 { "BelegNr",        "BelegNr" },
 { "Referenz",       "Referenz" },
 { "Betrag",         "Betrag" },
 { "Waehrung",       "Währung" },
 { "Text",           "Text" },
 { "Finanzkonto",    "KontoSoll" },
 { "Gegenkonto",     "KontoHaben" },
 { "Steuersatz",     "Steuersatz" },
 { "Kostenstelle1",  "Kostenstelle1" },
 { "Kostenstelle2",  "Kostenstelle2" },
 { "Notiz",          "Notiz" }
}



--
-- Hilfsfunktionen zur String-Behandlung
--

local DELIM = "," -- Delimiter

local function csvField (str)
  if str == nil or str == "" then
    return ""
  end
  return '"' .. string.gsub(str, '"', '""') .. '"'
end


local function concatenate (...)
  local catstring = ""
  for _, str in pairs({...}) do
    catstring = catstring .. ( str or "")
  end
  return catstring
end


--
-- WriteHeader: Erste Zeile der Exportdatei schreiben
--


function WriteHeader (account, startDate, endDate, transactionCount, options)
  -- Write CSV header.

  local line = ""
  for Position, Eintrag in ipairs(Exportdatei) do
    if Position ~= 1 then
      line = line .. DELIM
    end
    line = line .. csvField(Eintrag[2])
  end
  assert(io.write(MM.toEncoding(encoding, line .. linebreak, utf_bom)))
  print ("--------------- START EXPORT ----------------")
  
end


--
-- WriteHeader: Export abschließen
--

function WriteTail (account, options)
  print ("---------------  END EXPORT  ----------------")
end


function DruckeUmsatz(Grund, Umsatz)
  print (string.format( "%s: %s / %s %s / %s / %s / %s\n",
    Grund, Umsatz.Datum, Umsatz.Betrag, Umsatz.Waehrung,
    Umsatz.Kategorie, Umsatz.Verwendungszweck, Umsatz.Notiz) )
end


-- Extrahiere Metadaten aus dem Kategorie-Titel
--
-- Übergeben wird ein KategoriePfad, der die Kategorie-Hierarchie
-- in MoneyMoney wiedergibt. Jede Kategorie in diesem Pfad kann
-- ein Gegenkonto, einen Steuersatz oder eine Kostenstelle spezifizieren.
--
-- Wird ein Gegenkonto oder Steuersatz mehrfach spezifiziert, überschreibt
-- jeweils das jeweils rechte Feld den Wert seines Vorgängers. Kostenstellen
-- ergänzen sich, es dürfen aber nur maximal zwei unterschiedliche Kostenstellen
-- angegeben werden.

function UmsatzMetadaten (KategoriePfad, Kommentar)
  local KategoriePfadNeu
  local Gegenkonto, Steuersatz, KS1, KS2
  local AnzahlKostenstellen = 1
  local Kostenstellen = {}

  for Kategorie in string.gmatch(KategoriePfad, "([^\\]+)") do

    -- Ist dem Titel eine Konfiguration angehängt worden?
    local i, _, Metadaten = string.find ( Kategorie, "([%[{#].*)$")

    -- Dann Metadaten extrahieren
    if Metadaten then
      -- Metadaten aus dem Kategorie-Titel entfernen
      Kategorie = string.sub (Kategorie, 1, i - 1)

      -- Konto in eckigen Klammern ("[6851]")
      _, _, Konto = string.find (Metadaten, "%[(%d+)%]")
      if Konto then
        Gegenkonto = Konto
      end

      -- Steuersatz in geschweiften Klammern ("{VSt7}")
      _, _, Text = string.find (Metadaten, "{(.+)}")
      if Text then
        Steuersatz = Text
      end

      -- Kostenstelle 1 und 2 mit Hashzeichen ("#1000")
      for Nummer in string.gmatch(Metadaten, "#(%w+)%s*") do
        if AnzahlKostenstellen > 2 then
          error(string.format("Der Export wurde abgebrochen, da mehr als zwei Kostenstellen über die Kategorie angegeben wurde.\n\nKategorie:\t%s\n", Kategorie), 0)
        end
        Kostenstellen[AnzahlKostenstellen] = Nummer
        AnzahlKostenstellen = AnzahlKostenstellen + 1
      end
    end


    -- Leading/Trailing Whitespace aus dem verbliebenen Kategorie-Titel entfernen
    _, _, Kategorie = string.find (Kategorie, "%s*(.-)%s*$")


    -- Neuen Kategoriepfad aufbauen
    if KategoriePfadNeu then
      KategoriePfadNeu = KategoriePfadNeu .. " - " .. Kategorie
    else
      KategoriePfadNeu = Kategorie
    end

  end

  -- Umsatz-Kommentar nach Kostenstellen oder Steuersätzen durchsuchen

  KommentarNeu = Kommentar
  for KS in string.gmatch(Kommentar, "#(%w+)%s*") do
    if AnzahlKostenstellen > 2 then
      error(string.format("Der Export wurde abgebrochen, da zu viele weitere Kostenstellen in den Notizen angegeben wurden.\n\nKategorie:\t%s\nNotiz:\t%s\nKostenstelle 1:\t%s\nKostenstelle 2:\t%s", Kategorie, Notiz, Kostenstellen[1], Kostenstellen[2]), 0)
    end
    Kostenstellen[AnzahlKostenstellen] = KS
    AnzahlKostenstellen = AnzahlKostenstellen + 1
    KommentarNeu = string.gsub(KommentarNeu, "#" .. KS .. "%s*", "")
  end

  Begin, End, Text = string.find (Kommentar, "{(.+)}")
  if Text then
    Steuersatz = Text
    KommentarNeu = string.sub(KommentarNeu, 1, Begin) .. string.sub(KommentarNeu, End)
    KommentarNeu = string.gsub(KommentarNeu, "{" .. Text .. "}%s*", "")
  end

  -- Umsatz-Kommentar nach Konto durchsuchen

  Text = KommentarNeu:match "%[(%d+)%]"
  if Text then
    Gegenkonto = Text
    KommentarNeu = string.gsub(KommentarNeu, "%[" .. Text .. "]%s*", "")
    KommentarNeu = KommentarNeu:match "^%s*(.-)%s*$"
  end
  
  KommentarNeu = string.gsub(KommentarNeu, "%s*$", "")

  -- Alle extrahierten Werte zurückliefern
  return KategoriePfadNeu, KommentarNeu, Gegenkonto, Steuersatz, Kostenstellen[1], Kostenstellen[2]
end


--
-- WriteTransactions: Jede Buchung in eine Zeile der Exportdatei schreiben
--


function WriteTransactions (account, transactions, options)
  for _,transaction in ipairs(transactions) do

    -- Trage Umsatzdaten aus der Transaktion in der später zu exportierenden Form zusammen

    local Exportieren = true

    -- Zu übertragende Umsatzinformationen in eigener Struktur zwischenspeichern
    -- und einfache Feldinhalte aus Transaktion übernehmen

    local Umsatz = {
      Typ = transaction.bookingText,
      Name = transaction.name or "",
      Kontonummer = transaction.accountNumber or "",
      Bankcode = transaction.bankcode or "", 
      Datum = MM.localizeDate(transaction.bookingDate),
      Betrag = transaction.amount,
      Kommentar = transaction.comment or "",
      Verwendungszweck = transaction.purpose or "",
      Waehrung = transaction.currency or ""
    }


    -- Daten für den zu schreibenden Buchungsdatensatz
    local Buchung = {
      Umsatzart = Umsatz.Typ,
      Datum = Umsatz.Datum,
      Text = nil,
      Finanzkonto = nil,
      Gegenkonto = nil,
      Betrag = nil,
      Steuersatz = nil,
      Kostenstelle1 = nil,
      Kostenstelle2 = nil,
      BelegNr = string.gsub(io.filename, ".*/", ""), -- Dateiname des Exports ist die Belegnummer
      Referenz = Umsatz.Referenz,
      Waehrung = Umsatz.Waehrung,
      Notiz = ""
    }


    -- Einlesen der Konto-spezifischen Konfiguration aus den Konto-Attributen bzw. dem Kommentarfeld


    local Bankkonto = {}

    for Kennzeichen, Wert in pairs(account.attributes) do
      Bankkonto[Kennzeichen] = Wert
    end

    for Kennzeichen, Wert in string.gmatch(account.comment, "(%g+)=(%g+)") do
      Bankkonto[Kennzeichen] = Wert
    end

    -- Finanzkonto für verwendetes Bankkonto ermitteln

    if ( Bankkonto.Finanzkonto == "" ) then
      error ( string.format("Kein Finanzkonto für Konto %s gesetzt.\n\nBitte Feld 'Finanzkonto' in den benutzerdefinierten Feldern in den Einstellungen zum Konto setzen.", account.name ), 0)
    end

    Buchung.Finanzkonto = Bankkonto.Finanzkonto



    -- Extrahiere Buchungsinformationen aus dem Kategorie-Text und Kommentar

    Umsatz.Kategorie, Umsatz.Kommentar, Buchung.Gegenkonto, Buchung.Steuersatz,
    Buchung.Kostenstelle1, Buchung.Kostenstelle2 = UmsatzMetadaten (transaction.category, Umsatz.Kommentar)


    Buchung.Text = Umsatz.Name .. ": " .. Umsatz.Verwendungszweck .. ((Umsatz.Kommentar ~= "") and ( " (" .. Umsatz.Kommentar .. ")") or "")
    Buchung.Notiz = ((Umsatz.Kontonummer ~= "") and ( "(" .. Umsatz.Kontonummer .. ") ") or "") -- .. "[" .. Umsatz.Kategorie .. "] {" .. Umsatz.Typ .. "}"


    -- Vorgemerkte Buchungen nicht exportieren

    if ( transaction.booked == false) then
      Exportieren = false
    end

    -- Buchungen mit Betrag 0,00 nicht exportieren

    if ( transaction.amount == 0) then
      Exportieren = false
    end

    -- Buchungen mit Gegenkonto 0000 nicht exportieren

    if ( tonumber(Buchung.Gegenkonto) == 0) then
      Exportieren = false
    end

    -- Wenn für das Bankkonto eine Währung spezifiziert ist muss der Umsatz in dieser Währung vorliegen

    if Bankkonto.Waehrung and (Bankkonto.Waehrung ~= Umsatz.Waehrung) then
      Exportieren = false
    end



    -- Export der Buchung vorbereiten

    if (transaction.amount > 0) then
      Buchung.Betrag = MM.localizeNumber("0.00", transaction.amount)
    else
      Buchung.Betrag = MM.localizeNumber("0.00", - transaction.amount)
      Buchung.Finanzkonto, Buchung.Gegenkonto = Buchung.Gegenkonto, Buchung.Finanzkonto
    end
    

    -- Buchung exportieren

    if Exportieren then
      if options ~= nil then
        if options.checkedOnly and transaction.checkmark == false then
          error(string.format("Der Export wurde abgebrochen, da ein Umsatz nicht als erledigt markiert wurde.\n\nBetroffener Umsatz:\nKonto:\t%s\nDatum:\t%s\nName:\t%s\nBetrag:\t%.2f\t%s\nKategorie:\t%s\nZweck:\t%s\nNotiz:\t%s", account.name, Umsatz.Datum, Umsatz.Name, Umsatz.Betrag, Umsatz.Waehrung, Umsatz.Kategorie, Umsatz.Verwendungszweck, Umsatz.Notiz), 0)
        end
      end

      if Buchung.Finanzkonto and Buchung.Gegenkonto then

        local line = ""
        for Position, Eintrag in ipairs(Exportdatei) do
          if Position ~= 1 then
            line = line .. DELIM
          end
          line = line .. csvField(Buchung[Eintrag[1]])
        end
        assert(io.write(MM.toEncoding(encoding, line .. linebreak, utf_bom)))
      else
        DruckeUmsatz ("UNVOLLSTÄNDIG", Umsatz)
        if (Umsatz.Kategorie == nil) then
          error(string.format("Der Export wurde abgebrochen, da einem Umsatz keine Kategorie zugewiesen wurde.\n\nBetroffener Umsatz:\nKonto:\t%s\nDatum:\t%s\nName:\t%s\nBetrag:\t%s %s\nZweck:\t%s\nNotiz:\t%s", account.name, Umsatz.Datum, Umsatz.Name, Umsatz.Betrag, Umsatz.Waehrung, Umsatz.Verwendungszweck, Umsatz.Notiz), 0)
        else
          error(string.format("Der Export wurde abgebrochen, da die Kontenzuordnung für die Buchhaltung unvollständig ist (Finanzkonto: %s Gegenkonto: %s).\n\nBetroffener Umsatz:\nKonto:\t%s\nDatum:\t%s\nName:\t%s\nBetrag:\t%s\t%s\nKategorie:\t%s\nZweck:\t%s\nNotiz:\t%s", Buchung.Finanzkonto, Buchung.Gegenkonto, account.name, Umsatz.Datum, Umsatz.Name, Umsatz.Betrag, Umsatz.Waehrung, Umsatz.Kategorie, Umsatz.Verwendungszweck, Umsatz.Notiz), 0)
        end
      end
    else
        DruckeUmsatz ("ÜBERSPRUNGEN", Umsatz)
    end
  end
end


function WriteTail (account)
  -- Nothing to do.
end
