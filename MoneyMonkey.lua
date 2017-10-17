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


-- CSV Dateieinstellungen

local encoding     = "UTF-8"
local utf_bom      = false
local linebreak    = "\n"
local reverseOrder = false

-- Exportformat bei MoneyMoney anmelden

Exporter{version       = 1.00,
         format        = MM.localizeText("Buchungssätze"),
         fileExtension = "csv",
         reverseOrder  = reverseOrder,
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
 { "Bemerkung",      "Bemerkung" }
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


function WriteHeader (account, startDate, endDate, transactionCount)
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

function WriteTail (account)
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

function KategorieMetadaten (KategoriePfad)
  local KategorieNeuerPfad
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
      for Nummer in string.gmatch(Metadaten, "#(%d+)%s*") do
        if AnzahlKostenstellen == 3 then
          error(string.format("Mehr als zwei Kostenstellen in der Kategorie angegeben\n\nKategorie:\t%s\n", Kategorie), 0)
        end
        Kostenstellen[AnzahlKostenstellen] = Nummer
        AnzahlKostenstellen = AnzahlKostenstellen + 1
      end
    end

    -- Leading/Trailing Whitespace aus dem verbliebenen Kategorie-Titel entfernen
    _, _, Kategorie = string.find (Kategorie, "%s*(.-)%s*$")


    -- Neuen Kategoriepfad aufbauen
    if KategorieNeuerPfad then
      KategorieNeuerPfad = KategorieNeuerPfad .. " - " .. Kategorie
    else
      KategorieNeuerPfad = Kategorie
    end

  end
    
  -- Alle extrahierten Werte zurückliefern
  return KategorieNeuerPfad, Gegenkonto, Steuersatz, Kostenstellen[1], Kostenstellen[2]
end


--
-- WriteTransactions: Jede Buchung in eine Zeile der Exportdatei schreiben
--


function WriteTransactions (account, transactions)
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
      Notiz = transaction.comment or "",
      Verwendungszweck = transaction.purpose or "",
      Waehrung = transaction.currency or ""
    }


    -- Daten für den zu schreibenden Buchungsdatensatz
    local Buchung = {
      Umsatzart = Umsatz.Typ,
      Datum = Umsatz.Datum,
      Text = Umsatz.Name .. ": " .. Umsatz.Verwendungszweck .. ((Umsatz.Notiz ~= "") and ( " (" .. Umsatz.Notiz .. ")") or ""),
      Finanzkonto = nil,
      Gegenkonto = nil,
      Betrag = nil,
      Steuersatz = nil,
      Kostenstelle1 = nil,
      Kostenstelle2 = nil,
      BelegNr = "",
      Referenz = string.gsub(io.filename, ".*/", ""),
      Waehrung = Umsatz.Waehrung,
      Bemerkung = ""
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





    -- Extrahiere Buchungsinformationen aus dem Kategorie-Text

    Umsatz.Kategorie, Buchung.Gegenkonto, Buchung.Steuersatz,
    Buchung.Kostenstelle1, Buchung.Kostenstelle2 = KategorieMetadaten (transaction.category)

    Buchung.Bemerkung = concatenate ("(", Umsatz.Kontonummer, ") [", Umsatz.Kategorie, "] {", Umsatz.Typ, "}" )

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
      if transaction.checkmark == false then
        error(string.format("Abbruch des Exports, da ein Umsatz nicht als erledigt markiert wurde.\n\nBetroffener Umsatz:\nKonto:\t%s\nDatum:\t%s\nName:\t%s\nBetrag:\t%s\t%s\nKategorie:\t%s\nZweck:\t%s\nNotiz:\t%s", account.name, Umsatz.Datum, Umsatz.Name, Umsatz.Betrag, Umsatz.Waehrung, Umsatz.Kategorie, Umsatz.Verwendungszweck, Umsatz.Notiz), 0)
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
          error(string.format("Einem Umsatz wurde keine Kategorie zugewiesen. Export daher nicht möglich.\n\nBetroffener Umsatz:\nKonto:\t%s\nDatum:\t%s\nName:\t%s\nBetrag:\t%s %s\nZweck:\t%s\nNotiz:\t%s", account.name, Umsatz.Datum, Umsatz.Name, Umsatz.Betrag, Umsatz.Waehrung, Umsatz.Verwendungszweck, Umsatz.Notiz), 0)
        else
          error(string.format("Abbruch des Exports, da Kontenzuordnung unvollständig ist (Finanzkonto: %s Gegenkonto: %s).\n\nBetroffener Umsatz:\nKonto:\t%s\nDatum:\t%s\nName:\t%s\nBetrag:\t%s\t%s\nKategorie:\t%s\nZweck:\t%s\nNotiz:\t%s", Buchung.Finanzkonto, Buchung.Gegenkonto, account.name, Umsatz.Datum, Umsatz.Name, Umsatz.Betrag, Umsatz.Waehrung, Umsatz.Kategorie, Umsatz.Verwendungszweck, Umsatz.Notiz), 0)
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