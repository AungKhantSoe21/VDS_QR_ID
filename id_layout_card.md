# ID Card Layout & Data Structure

```
+-------------------------------------------------------------------------------+
|  [ Coat of Arms ]    [ Country Name (Burmese + English) ]    [ National Flag ]|
+-------------------------------------------------------------------------------+
|                 |                                                             |
|                 |  Name Label                                                 |
|                 |  Burmese Name / English Name                                |
|                 |                                                             |
|                 |  UID Label                      +------------------------+  |
|  [ PORTRAIT ]   |  UID Value                      |                        |  |
|     PHOTO       |                                 |        QR CODE         |  |
|                 |  National Reg. Label            |                        |  |
|                 |  National Reg. Value            +------------------------+  |
|                 |                                                             |
|                 |  Date of Birth     Gender     Date of Expiry                |
|                 |  DD MMM YYYY         M          DD MMM YYYY                 |
+-------------------------------------------------------------------------------+
|=========================== [ DECORATIVE BORDER ] =============================|
```

---

## Grid Structure Definition

### 1. Header (Top Row)
* **Layout:** 3-column inline flex / table (Left: `auto`, Center: `flex-1`, Right: `auto`)
* **Left Element:** State Emblem / Coat of Arms
* **Center Element:** Dual-language header centered horizontally
  * Top: State text in Burmese (Large, bold)
  * Bottom: `THE REPUBLIC OF THE UNION OF MYANMAR` (Uppercase)
* **Right Element:** National Flag icon

---

### 2. Main Content Body
* **Layout:** 2-column split 
  * **Left Column (width ~ 30%):** Cardholder portrait image, bottom-aligned.
  * **Right Column (width ~ 70%):** Text fields and verification data.

---

### 3. Field Breakdown (Right Column)

#### Block A: Name Section
* **Position:** Top full-width of right column
* **Label:** `အမည် / Name` (Muted / small font)
* **Value:** `ဦးသီဟအောင် / U Thiha Aung` (Large, prominent bold font)

#### Block B: UID & Security
* **Layout:** 2-column split within right section
* **Left Sub-block:**
  * **Label:** `UID No.`
  * **Value:** `0123456789`
* **Right Sub-block:**
  * **Element:** 2D QR Code (Aligned to right edge)

#### Block C: National ID Number
* **Position:** Below UID field
* **Label:** `နိုင်ငံသားစိစစ်ရေးကတ်ပြားအမှတ်`
* **Value:** `၁၂ / အမ ( နိုင် ) ၀၁၅၄၃၂`

#### Block D: Dates & Gender Footer Row
* **Layout:** 3-column inline grid (`1fr 1fr 1fr`)
* **Col 1 (Date of Birth):**
  * **Label:** `Date Of Birth`
  * **Value:** `11 Nov 1995`
* **Col 2 (Gender):**
  * **Label:** `Gender`
  * **Value:** `M`
* **Col 3 (Expiry Date):**
  * **Label:** `Date Of Expiry`
  * **Value:** `29 Oct 2030`

---

## Styling & Theme Notes

* **Primary Background:** Pale green guilloche (security print pattern) overlaid with central architectural line artwork.
* **Accent Colors:** Deep green headers, dark navy/black primary text.
* **Typography Hierarchy:**
  * **Labels:** Small, gray/muted color, dual-language where applicable.
  * **Values:** Medium-to-large dark text; Burmese text uses traditional typeface, English text uses standard sans-serif.
* **Frame:** Decorative repeating geometric border along the bottom edge.