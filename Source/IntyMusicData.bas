'IntyMusic by Marco A. Marrero.  
'-------
'IntyBasic notes are values from 1 to 61, C2 to C7. In most of these first value is dummy, notes start from 1-18
'To understand all these values, look at the spreadsheet, it mostly documents what I am trying to documents
'It also helps a lot understanding how STIC sprites and GRAM cards work, see http://wiki.intellivision.us/index.php?title=STIC
'

'---Note relative to screen (1-18). 2 notes per card, FIRST ENTRY IS DUMMY (duplicated 1st value) (Btw, I am shouting at myself, I keep forgetting what I did...)
IntyNoteOnscreen:
DATA 1,1,1,1,1,2,2,2,3,3,3,3,4,4,4,5,5,5,6,6,6,6,7,7,7,8,8,8,8,9,9,9,10,10,10,10,11,11,11,12,12,12,13,13,13,13,14,14,14,15,15,15,15,16,16,16,17,17,17,17,18,18,18,18

'--Note Alpha/letter... was GROM card values. C,D,E,F,G,A or B etc..  no # here. FIRST ENTRY IS DUMMY, I duplicated 1st value
'--Now its a GRAM Card... (Sprite 32+(letter A=0) *8)+bit11 (2048)
IntyNoteLetter:
DATA 2320,2320,2320,2328,2328,2336,2344,2344,2352,2352,2304,2304,2312,2320,2320,2328,2328,2336,2344,2344,2352,2352,2304,2304,2312,2320,2320,2328,2328,2336,2344,2344,2352,2352,2304,2304,2312,2320,2320,2328,2328,2336,2344,2344,2352,2352,2304,2304,2312,2320,2320,2328,2328,2336,2344,2344,2352,2352,2304,2304,2312,2320,2320,2320

'--Sharp notes, according to value. 24=GROM Card #. FIRST ENTRY IS DUMMY
IntyNoteSharp:
'DATA " "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," "
'DATA 0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0
'---Now its a GRAM card... Sprite 39*8 + bit11 (2048)
DATA 0,0,2360,0,2360,0,0,2360,0,2360,0,2360,0,0,2360,0,2360,0,0,2360,0,2360,0,2360,0,0,2360,0,2360,0,0,2360,0,2360,0,2360,0,0,2360,0,2360,0,0,2360,0,2360,0,2360,0,0,2360,0,2360,0,0,2360,0,2360,0,2360,0,0,0

'--- Ocatave according to note value, =(Octave*8)+(16*8) = GROM card # for 2,3,4,5,6,7-- FIRST DATA IS DUMMY
IntyNoteOctave:
'DATA 0,144,144,144,144,144,144,144,144,144,144,144,144,152,152,152,152,152,152,152,152,152,152,152,152,160,160,160,160,160,160,160,160,160,160,160,160,168,168,168,168,168,168,168,168,168,168,168,168,176,176,176,176,176,176,176,176,176,176,176,176,184
'---Now its a GRAM card... Starting from sprite 48*8 + bit11 (2048). FIRST VALUE IS DUMMY
DATA 2432,2432,2432,2432,2432,2432,2432,2432,2432,2432,2432,2432,2432,2440,2440,2440,2440,2440,2440,2440,2440,2440,2440,2440,2440,2448,2448,2448,2448,2448,2448,2448,2448,2448,2448,2448,2448,2456,2456,2456,2456,2456,2456,2456,2456,2456,2456,2456,2456,2464,2464,2464,2464,2464,2464,2464,2464,2464,2464,2464,2464,2472,2472

'--GRAM Card to use------- Positioned horizontally -----
'I combined GRAM cards. 2 notes per card. I wont display adjacent notes, only 1 will be shown. FIRST VALUE IS DUMMY
IntyNoteGRAM:
DATA 2056,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2056,2072,2064,2080,2056,2072,2064,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2080,2056,2064,2080,2056,2072,2056,2056,2072,2064,2080,2056,2072,2064,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2080,2056,2064

'-used to draw top of display, with vertical lines
IntyNoteBlankLine:
DATA 0,0,0,2048,2048,2048,2048,2048,0,2048,2048,2048,2048,2048,0,0,0,0,0,0,0,0

'----Piano! GRAM+(Sprite24*8),GRAM+(Sprite25*8), etc-----
'There are 2 1/2 key per GRAM card for the piano, 4 different sprites for hilite. 7 combinations 2 octaves...
'GRAM cards: CD,EF,GA,BC*,DE*,FG*,AB.  (*=same cards as EF,AB,CD). See source image to understand what all this means.
IntyPiano:
'2272= Char284 * 8
DATA 2272,2208,2192,2200,2192,2296,2208,2296,2208,2192,2200,2192,2296,2208,2296,2208,2192,2200,2192,2296,2208,2208,2208

'Sprite to show. 1st one is not dummy, but it wont be played. 
IntyPianoSprite:
DATA 2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2264

'Key offstet position... on the source spreadsheet its a row of offsets (0-7) + card position (0,8,16,etc)
'In the source image, I drew all possibilities, and practically had to count pixels to get the correct offset.
IntyPianoSpriteOffset:
DATA 4,0,2,4,6,8,12,14,16,18,20,22,24,28,30,32,34,36,40,42,44,46,48,50,52,56,58,60,62,64,68,70,72,74,76,78,80,84,86,88,90,92,96,98,100,102,104,106,108,112,114,116,118,120,124,126,128,130,132,134,136,140,142,144,146,148,152,154,156

