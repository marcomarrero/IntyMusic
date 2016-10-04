'IntyMusic by Marco A. Marrero.
'IntyMusic_Player.bas | Main code.
'Public domain, feel free to use/modify. Feel free to contact me in the Intellivision Programming forum @ AtariAge.com

WAIT
'--- read cards, 16 at a time
DEFINE 0,16,Sprite0:WAIT
DEFINE 16,16,Sprite16:WAIT
DEFINE 32,16,Sprite32:WAIT
DEFINE 48,8,Sprite48:WAIT

'--- arrays used to copy values from IntyBasic music player, in IntyBasic_epilogue.asm, 3 voices/sound channels -----
DIM iMusicNote(3)			'Notes 0,1,2	(from IntyBasic_epilogue)
DIM iMusicVol(3)			'Volume (from IntyBasic_epilogue)
DIM iMusicWaveForm(3)		'Waveform. Will hit 1 for new notes.

DIM iMusicNoteLast(3)		'Previous notes
DIM iMusicVolumeLast(3)	'store last volume values

'--This one has 3 timing/counter variables from IntyBasic_epilogue---
DIM iMusicTime(3)			' _music_tc - 1 (time base), _music_t (note count), and _music_frame (1=skipped a frame on ntsc)

'---
DIM iMusicDrawNote(3)		'Draw new note, by voice channel

'---------------
IntyMusicReset:

'----show title screen and credits--- also prints vertical song name ---
IF INTYMUSIC_FANFOLD THEN #IntyMusicBlink=CS_ADVANCE ELSE #IntyMusicBlink=0
GOSUB IntyMusicCredits
GOSUB WaitForKeyDownThenUp	
ScrollDelay=5:GOSUB ScrollStaffToStartPlay

'--Volume graph display----
IF INTYMUSIC_PLAY_VOLUME<2 OR INTYMUSIC_PLAY_VOLUME>15 THEN INTYMUSIC_PLAY_VOLUME=15	'-- Volume must be 2 to 15..
#CharVolume = (INTYMUSIC_VOLUMECARD*8) + 2048				'--GRAM card for volume: 40, 41 or 43 for volume bar. I prefer 43.
#NotePosition = 97+12 -(15-INTYMUSIC_PLAY_VOLUME) + ZOOMY2	'-- 14 seems too low, 13 is ok, 12 touches piano noticeably, etc.

'==== PLAY! ====
WAIT
PLAY VOLUME INTYMUSIC_PLAY_VOLUME
PLAY MyMusic

'----init----
iMusicScroll=0			'Need to scroll screen?
iMusicScrollCount=0		'Scroll counter
Toggle=1					'Piano hilite index, 0 or 1 (Ill XOR it later)
KeyClear=0

'---- main loop -----
PlayLoop:
	WAIT 
	
	'--- The iMusicScroll is modified in ON FRAME GOSUB... code is in DoStuffAfterWait: PROCEDURE ---
	IF iMusicScroll<>0 THEN	
		CALL MUSICSCROLL		'Scroll... I am only moving part of the screen to avoid redrawing
		iMusicScroll=0
		
		'---Alternate colors if enabled---
		#BACKTAB(0)=#IntyMusicBlink:#BACKTAB(220)=#IntyMusicBlink			
		PRINT AT 221		'<--- Do NOT remove! 	
		
		'---Draw letter, C3# A4 B5-----	
		FOR iVoice=0 TO 2
			IntyNote=iMusicNote(iVoice)	'--Get note value, look-up tables 
			#x=iMusicNoteColor(iVoice)	'Get note color
			
			PRINT 2280+iMusicDrawNote(iVoice)				'---Note, blink if it is a new note 
			PRINT #CharVolume+#iMusicPianoColorB(iVoice)		'---Volume meter, background (Color is Hilite color of piano key)
			PRINT IntyNoteLetter(IntyNote)+#x				'---Note letter (CDEFGAB)
			PRINT IntyNoteSharp(IntyNote)+#x				'---Sharp?
			PRINT IntyNoteOctave(IntyNote)+#x,0			'---Octave number, space (0)
		NEXT iVoice
			
		'----Done updating lower screen. Clear top line, draw staff---
		FOR iMusicX=1 TO 18
			#BACKTAB(iMusicX)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
		NEXT iMusicX
		
		'---Use sprites to "hilite" piano keys and draw notes-----
		Toggle=Toggle XOR 1	'Toggle piano key hilite, 1 or 0
		FOR iVoice=0 TO 2
			IntyNote=iMusicNote(iVoice)	'--Get note 
			
			'---Draw Note. Up to 2 notes per card. I used spreadsheet for lookup data: GRAM card, position, offset, etc.--
			IF iMusicDrawNote(iVoice) THEN 
				#BACKTAB(IntyNoteOnscreen(IntyNote))=IntyNoteGRAM(IntyNote) + iMusicNoteColor(iVoice)				
				iMusicDrawNote(iVoice)=0
			END IF
			
			'---Overlay sprites on piano keys. Flash colors---
			IF Toggle THEN #x=#iMusicPianoColorA(iVoice) ELSE #x=#iMusicPianoColorB(iVoice)				
			IF iMusicVol(iVoice)=0 THEN
				resetsprite(iVoice)
			ELSE
				SPRITE iVoice,16 + VISIBLE + IntyPianoSpriteOffset(IntyNote),88 + ZOOMY2, IntyPianoSprite(IntyNote) + #x
			END IF				
		NEXT iVoice
	END IF '<--iMusicTime
	
	'---Update volume sprite.. It just moves offscreen instead of changing shape --- 
	iMusicX=8
	FOR iVoice=0 TO 2
		'Volume meter...
		SPRITE iVoice+5,16 + VISIBLE + iMusicX,(#NotePosition-iMusicVol(iVoice))+ZOOMY2, SPR40 + BEHIND + #iMusicPianoColorA(iVoice) 
		iMusicX=iMusicX+48		
	NEXT iVoice	
	
	'---- Clr: user reset----
	IF Cont.KEY=12 THEN 
		KeyClear=1
	ELSE
		IF KeyClear THEN 
			IF Cont.KEY=10 THEN GOTO KillMusicAndRestart
		END IF
		KeyClear=0
	END IF	
	
	'----Music stop?-----
	IF MUSIC.PLAYING=0 THEN
		GOTO KillMusicAndRestart
	END IF
	
GOTO PlayLoop

'---Forcefully kills music
KillMusicAndRestart:
	WAIT:PLAY OFF						
	WAIT:SOUND 0,1,0:	SOUND 1,1,0:	SOUND 2,1,0:SOUND 4,1,$38
	CALL IMUSICKILL	'works too well...
GOTO IntyMusicReset

'********
'-- New way to synchronize. Now I am sure I am not skipping any frame in any way
'-- This is called at every frame, I skip every 6th frame ---
DoStuffAfterWait: PROCEDURE	

	IF MUSIC.PLAYING<>0 THEN
		'--Get music player data from IntyBasic_epilogue ASM variables ---
		CALL IMUSICGETINFOV2(VARPTR iMusicVol(0), VARPTR iMusicNote(0), VARPTR iMusicWaveForm(0),VARPTR iMusicTime(0))
				
		'--Check values if frame was not skipped (every 6 frames on NTSC)
		IF iMusicTime(2)<>1 THEN
			
			'--Force scrolling according to INTYMUSIC_NEW_AUTO_SCROLL. 0=pause between notes (or wait 256 frames), 1=scroll at every frame, 2=skip one frame, etc.
			'--- On any note change screen will scroll, and this value gets reset.
			iMusicScrollCount=iMusicScrollCount+1
			IF iMusicScrollCount=INTYMUSIC_NEW_AUTO_SCROLL THEN iMusicScrollCount=0:iMusicScroll=1
			
			'--- check if new note played
			FOR #Channel=0 TO 2
				IF iMusicNoteLast(#Channel)<>iMusicNote(#Channel) THEN 
					iMusicNoteLast(#Channel)=iMusicNote(#Channel)
					iMusicDrawNote(#Channel)=iMusicNoteColor(#Channel)
					iMusicScroll=1:iMusicScrollCount=0	'--Yes, note changed, scroll down
				'---check if waveform index zeroed (same note was hit again), will be 1 after VBLANK
				ELSEIF iMusicWaveForm(#Channel)=1 THEN
					iMusicDrawNote(#Channel)=iMusicNoteColor(#Channel)
					iMusicScroll=1:iMusicScrollCount=0	'--Yes, note restarted, scroll down
				END IF
			NEXT #Channel	
		END IF 'iMusicTime
	END IF	
END

'**********************************************************************
'== Assembly language routines ========================================
'    _______________
'___/ IMUSICGETINFO2 \_________________________________________________
'Get IntyBasic_epilogue data onto IntyBasic. Ill copy note, volume, and timing variables
'Call IMUSICGETINFO(VARPTR iMusicVol(0-2), VARPTR iMusicNote(0-2), VARPTR iMusicWaveform(0-2),VARPTR iMusicTime(0-3))	
ASM IMUSICGETINFOV2: PROC	
'r0 = 1st parameter, VARPTR iMusicVol(0 to 2)
'r1 = 2nd parameter, VARPTR iMusicNote(0 to 2)
'r2 = 3rd parameter, VARPTR iMusicWaveform(0 to 2)
'r3 = 4rd parameter, VARPTR iMusicTime(0 to 2)
'asm pshr r5				;push return
		
'--- iMusicTime(0)=_music_t (Time Base),iMusicTime(1)=_music_tc (note time), iMusicTime(2)=_music_frame (0 to 5) 0=skipped frame!
	asm movr	r3,r4				; r3 --> r4 		r4=&iMusicTime(0)
	asm mvi _music_t,r3			; _music_t --> r3 (time base)
	asm decr r3 					; r3-- (time base=time base - 1)
	asm mvo@ r3,r4				; r3 --> [r4++]	
	
	asm mvi	_music_tc,r3			; _music_tc --> r3 (time)	
	asm mvo@ r3,r4				; r3 --> [r4++]

	asm mvi	_music_frame,r3		; _music_frame --> r3 (time, 0 to 5). In pal, it should be always zero...
	asm add	_ntsc,r3				; if NTSC then r3++ (time is now 1 to 6, now I can test if it is 1 when skipped)
	asm mvo@ r3,r4				; r3 --> [r4++]
	
	asm cmpi #1,r3				; if (r3==1) then music skipped! We already have all the values, no need to re-read
	asm beq @@GoodBye		

'---- get volume, to know when same note played again ---
	asm movr	r0,r4			;r0 --> r4 (r4=r0=&iMusicVol(0))
	
	asm mvi	_music_vol1,r3	;  --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_vol2,r3	; --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_vol3,r3	; --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	
'--- get notes ---
	asm movr	r1,r4			;r1 --> r4. (r4=&iMusicNote(0))
	asm mvi	_music_n1,r3		;_music_n1 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_n2,r3 	;_music_n2 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_n3,r3		;_music_n3 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]

'--- Get WaveForm (to detect if same note went again) ----iMusicWaveform(x) ----
	asm movr r2,r4				;r2 --> r4  (r4= &iMusicWaveform(0))
	asm mvi _music_s1,r3
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi _music_s2,r3
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi _music_s3,r3
	asm mvo@ r3,r4				; r3 --> [r4++]

'-------------------------------------------------------------	
asm @@GoodBye:
	asm jr	r5				;return 
asm ENDP


'    ____________
'___/ MUSICSCROLL \____________________ 
'Only Scroll 10 rows, and only columns 2 to 18 (17 lines). 
'Copying from bottom to top, I am guessing it is better in case VBLANK is over and screen refreshes while copying...
ASM MUSICSCROLL: PROC	
		
	asm mvii #$0200 + 198,r2		;#BackTAB + 198--> R2
	asm mvii	#$0200 + 178,r3		;Line above --> r3 
	asm mvii #9,r1				;Loop 9 lines
	asm mvii #2,r4				;Skip 2 chars
	
asm @@CopyLoop:
	asm REPEAT 18
		asm mvi@ r3,r0		;[r3] --> R0
		asm decr r3
		asm mvo@ r0,r2		;r0 --> [R2]		
		asm decr r2 
	asm ENDR
	
	asm subr r4,r2		;skip 3 chars 
	asm subr r4,r3 
	
	asm decr r1			;done row..
	asm bne @@CopyLoop
	
	asm jr	r5				;return
asm ENDP		


'    ____________
'___/ IMUSICKILL \___________________________
'PLAY NONE seems not to work.... This kills IntyBasic musis player notes. I wonder if I should also clear other things
ASM IMUSICKILL: PROC	
		
'--- kill notes ---
	asm xorr r0,r0			;clear r0
	asm mvo	r0,_music_n1
	asm mvo	r0,_music_n2
	asm mvo 	r0,_music_n3
	asm jr	r5				;return 
asm ENDP

'**********************************************************************
'=========IntyMusic credits/title screen================

'I created a playlist, 42K can fit about 10 songs, but it is a nigtmare 
'making things fit segments. If it does not fit, youll get crashes, crazy behavior, garbage data,etc.
'
'I mistakenly tried asm org $D000, instead of asm org $E000 to test... booo!!!!!!
'Anywhow, I made demo code is in the PlayListDemo folder, and I explain a bit better what the $E000 test means.
'

IntyMusicCredits: PROCEDURE
	FOR #x=0 TO 7:resetsprite(#x):NEXT #x
	CLS
	WAIT
	GOSUB DrawMainScreen

	'---me---		
	PRINT AT 160 COLOR FG_BLUE,"\285"
	PRINT COLOR FG_BLACK," IntyMusic Player "
	PRINT COLOR FG_BLUE,"\286"
	PRINT AT 182 COLOR FG_BLACK,"by Marco Marrero"

	GOSUB IntyMusicInit_Credits
	IntyPianoKeys=18:GOSUB DrawPianoX
			
	PRINT AT 221 COLOR FG_BLUE,"Any button to play"
	PRINT AT 0	
	GOSUB DrawFanFoldBorder
	
END

DrawMainScreen: PROCEDURE
	iMusicX=0			
	'--draw a bit of the staff	
	FOR #x=0 TO 3*20
		#BACKTAB(#x)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
		iMusicX=iMusicX+1:IF iMusicX>19 THEN iMusicX=0
	NEXT #x

	'Draw &
	PRINT AT 9 COLOR 0,"\277\269\272\261"
	PRINT AT 29,"\278\270\273\262"
	
	'draw )
	PRINT AT 5,"\271\263"
	PRINT AT 25,"\273\262"
	PRINT AT 46,"\279"

	IntyPianoKeys=19:GOSUB DrawPianoX	'Draw all 20 piano keys
END

DrawFanFoldBorder: PROCEDURE
IF INTYMUSIC_FANFOLD THEN	'---Alternate colors
	iMusicX=0
	FOR KeyClear=1 TO 10
		#BACKTAB(iMusicX)=#BACKTAB(iMusicX)+#IntyMusicBlink
		iMusicX=iMusicX+20
	NEXT KeyClear		
END IF
END

'---- 
WaitForKeyDownThenUp: procedure
	' Wait for a key to be pressed. Ignore CLR
	DO
		do 
			wait
		loop while CONT=0 OR CONT.KEY=10

		' Wait for a key to be released
		do 
			wait
		loop while CONT<>0
	LOOP WHILE CONT.KEY=10
end

'----
DrawPianoX: PROCEDURE			'- Draw piano, clear bottom lines 1st---
	FOR #x=0 TO IntyPianoKeys
		#BACKTAB(200+#x)= IntyPiano(#x)		
	NEXT #x		
	
	#BACKTAB(220)=#IntyMusicBlink
	FOR #x=221 TO 238 
		#BACKTAB(#x)= 0
	NEXT #x	
END


'--Scroll staff, slowly, used before playing song. Also print song title.
ScrollStaffToStartPlay: PROCEDURE		
	FOR iMusicX=1 TO 12
		SCROLL 0,0,3		'Scroll upwards (move things down)
		WAIT				
		IntyPianoKeys=18:GOSUB DrawPianoX
				
		IF INTYMUSIC_FANFOLD THEN #BACKTAB(0)=#IntyMusicBlink
		FOR #x=1 TO 19
			#BACKTAB(#x)=IntyNoteBlankLine(#x)	+ INTYMUSIC_STAFF_COLOR
		NEXT #x	
				
		'Print song name -- I am scrolling so I am printing one char at a time...
		IF INTYMUSIC_SONG_TITLE THEN 
			#BACKTAB(19)=MyMusicName(12-iMusicX)*8 + INTYMUSIC_TITLE_COLOR	
			
			IF iMusicX<10 THEN
				#BACKTAB(239)=0
			ELSEIF iMusicX=10 THEN 				
				#BACKTAB(219)=0		'Stop drawing all piano keys when title is nearby			
				#BACKTAB(239)=0
			END IF
		END IF
			
		'sleep...		
		IF ScrollDelay>0 THEN FOR #x=1 TO ScrollDelay: WAIT:NEXT #x
	NEXT iMusicX 
END

'============== IntyMusic Look-up values ==============================
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

'**********************************************************************
'============== IntyMusic graphics ==============================
'---- IntyMusic5.png --- Saturday, October 1, 2016

'===Sprite:0 == Chr:256===== [8,8]
Sprite0:
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40

'===Sprite:1 == Chr:257===== [8,8]
'Sprite1:
	BITMAP ".#.#...."	'$50
	BITMAP ".#.#...."	'$50
	BITMAP ".#.#...."	'$50
	BITMAP ".#.#...."	'$50
	BITMAP ".###...."	'$70
	BITMAP "####...."	'$F0
	BITMAP "####...."	'$F0
	BITMAP ".##....."	'$60

'===Sprite:2 == Chr:258===== [8,8]
'Sprite2:
	BITMAP ".#....#."	'$42
	BITMAP ".#....#."	'$42
	BITMAP ".#....#."	'$42
	BITMAP ".#....#."	'$42
	BITMAP ".#..###."	'$4E
	BITMAP ".#.####."	'$5E
	BITMAP ".#.####."	'$5E
	BITMAP ".#..##.."	'$4C

'===Sprite:3 == Chr:259===== [8,8]
'Sprite3:
	BITMAP ".#.#...."	'$50
	BITMAP ".#.#..#."	'$52
	BITMAP ".#.#.#.#"	'$55
	BITMAP ".#.#..#."	'$52
	BITMAP ".###...."	'$70
	BITMAP "####...."	'$F0
	BITMAP "####...."	'$F0
	BITMAP ".##....."	'$60

'===Sprite:4 == Chr:260===== [8,8]
'Sprite4:
	BITMAP ".#....#."	'$42
	BITMAP ".#.#..#."	'$52
	BITMAP ".##.#.#."	'$6A
	BITMAP ".#.#..#."	'$52
	BITMAP ".#..###."	'$4E
	BITMAP ".#.####."	'$5E
	BITMAP ".#.####."	'$5E
	BITMAP ".#..##.."	'$4C

'===Sprite:5 == Chr:261===== [8,8]
'Sprite5:
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "#####..."	'$F8
	BITMAP "#..###.."	'$9C
	BITMAP "....###."	'$0E

'===Sprite:6 == Chr:262===== [8,8]
'Sprite6:
	BITMAP "......##"	'$03
	BITMAP "......##"	'$03
	BITMAP "#...####"	'$8F
	BITMAP "#######."	'$FE
	BITMAP "######.."	'$FC
	BITMAP ".####..."	'$78
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:7 == Chr:263===== [8,8]
'Sprite7:
	BITMAP "........"	'$00
	BITMAP ".####..."	'$78
	BITMAP "######.."	'$FC
	BITMAP "#######."	'$FE
	BITMAP "###.####"	'$EF
	BITMAP "##...###"	'$C7
	BITMAP "##....##"	'$C3
	BITMAP "#.....##"	'$83

'===Sprite:8 == Chr:264===== [8,8]
'Sprite8:
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "#.#.#.#."
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:9 == Chr:265===== [8,8]
'Sprite9:
	BITMAP "...#...."	'$10
	BITMAP "...#...."	'$10
	BITMAP "...#...."	'$10
	BITMAP "...#...."	'$10
	BITMAP ".###...."	'$70
	BITMAP "####...."	'$F0
	BITMAP "####...."	'$F0
	BITMAP ".##....."	'$60

'===Sprite:10 == Chr:266===== [8,8]
'Sprite10:
	BITMAP "......#."	'$02
	BITMAP "......#."	'$02
	BITMAP "......#."	'$02
	BITMAP "......#."	'$02
	BITMAP "....###."	'$0E
	BITMAP "...####."	'$1E
	BITMAP "...####."	'$1E
	BITMAP "....##.."	'$0C

'===Sprite:11 == Chr:267===== [8,8]
'Sprite11:
	BITMAP "...#...."	'$10
	BITMAP "...#..#."	'$12
	BITMAP "...#.#.#"	'$15
	BITMAP "...#..#."	'$12
	BITMAP ".###...."	'$70
	BITMAP "####...."	'$F0
	BITMAP "####...."	'$F0
	BITMAP ".##....."	'$60

'===Sprite:12 == Chr:268===== [8,8]
'Sprite12:
	BITMAP "......#."	'$02
	BITMAP "..#...#."	'$22
	BITMAP ".#.#..#."	'$52
	BITMAP "..#...#."	'$22
	BITMAP "....###."	'$0E
	BITMAP "...####."	'$1E
	BITMAP "...####."	'$1E
	BITMAP "....##.."	'$0C

'===Sprite:13 == Chr:269===== [8,8]
'Sprite13:
	BITMAP "...#####"	'$1F
	BITMAP ".#######"	'$7F
	BITMAP "####...."	'$F0
	BITMAP "#......."	'$80
	BITMAP "...##..."	'$18
	BITMAP "..####.."	'$3C
	BITMAP ".##.###."	'$6E
	BITMAP ".#..####"	'$4F

'===Sprite:14 == Chr:270===== [8,8]
'Sprite14:
	BITMAP "..######"	'$3F
	BITMAP "########"	'$FF
	BITMAP "###....#"	'$E1
	BITMAP "#.....##"	'$83
	BITMAP "##...###"	'$C7
	BITMAP "#######."	'$FE
	BITMAP ".#####.."	'$7C
	BITMAP "..###..."	'$38

'===Sprite:15 == Chr:271===== [8,8]
'Sprite15:
	BITMAP ".#......"	'$40
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP "..##...#"	'$31
	BITMAP "..##..##"	'$33
	BITMAP "..###.##"	'$3B
	BITMAP "...##.##"	'$1B
	BITMAP "...##..#"	'$19

'===Sprite:16 == Chr:272===== [8,8]
Sprite16:
	BITMAP "#......."	'$80
	BITMAP "###....."	'$E0
	BITMAP "####...."	'$F0
	BITMAP ".####..."	'$78
	BITMAP "..###..."	'$38
	BITMAP "...###.#"	'$1D
	BITMAP ".#######"	'$7F
	BITMAP "#######."	'$FE

'===Sprite:17 == Chr:273===== [8,8]
'Sprite17:
	BITMAP "...###.."	'$1C
	BITMAP "....###."	'$0E
	BITMAP ".....###"	'$07
	BITMAP "......##"	'$03
	BITMAP ".......#"	'$01
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:18 == Chr:274===== [8,8]
'Sprite18:
	BITMAP "########"	'$FF
	BITMAP "#..#..##"	'$93
	BITMAP "#..#..##"	'$93
	BITMAP "#..#..##"	'$93
	BITMAP "#..#..##"	'$93
	BITMAP "...#...#"	'$11
	BITMAP "...#...#"	'$11
	BITMAP "########"	'$FF

'===Sprite:19 == Chr:275===== [8,8]
'Sprite19:
	BITMAP "########"	'$FF
	BITMAP "#.###.##"	'$BB
	BITMAP "#.###.##"	'$BB
	BITMAP "#.###.##"	'$BB
	BITMAP "#.###.##"	'$BB
	BITMAP "...#...#"	'$11
	BITMAP "...#...#"	'$11
	BITMAP "########"	'$FF

'===Sprite:20 == Chr:276===== [8,8]
'Sprite20:
	BITMAP "########"	'$FF
	BITMAP "..###.##"	'$3B
	BITMAP "..###.##"	'$3B
	BITMAP "..###.##"	'$3B
	BITMAP "..###.##"	'$3B
	BITMAP "...#...#"	'$11
	BITMAP "...#...#"	'$11
	BITMAP "########"	'$FF

'===Sprite:21 == Chr:277===== [8,8]
'Sprite21:
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP ".......#"	'$01
	BITMAP "..##..##"	'$33
	BITMAP ".####.##"	'$7B
	BITMAP "#####.#."	'$FA
	BITMAP "#####.#."	'$FA

'===Sprite:22 == Chr:278===== [8,8]
'Sprite22:
	BITMAP "#.##..#."	'$B2
	BITMAP "##...###"	'$C7
	BITMAP ".#######"	'$7F
	BITMAP "..######"	'$3F
	BITMAP ".......#"	'$01
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:23 == Chr:279===== [8,8]
'Sprite23:
	BITMAP ".###.###"	'$77
	BITMAP ".###.###"	'$77
	BITMAP ".###.###"	'$77
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:24 == Chr:280===== [8,8]
'Sprite24:
	BITMAP "........"	'$00
	BITMAP "###....."	'$E0
	BITMAP "###....."	'$E0
	BITMAP "###....."	'$E0
	BITMAP "###....."	'$E0
	BITMAP "........"	'$00
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:25 == Chr:281===== [8,8]
'Sprite25:
	BITMAP "........"	'$00
	BITMAP "##......"	'$C0
	BITMAP "##......"	'$C0
	BITMAP "##......"	'$C0
	BITMAP "##......"	'$C0
	BITMAP "###....."	'$E0
	BITMAP "###....."	'$E0
	BITMAP "........"	'$00

'===Sprite:26 == Chr:282===== [8,8]
'Sprite26:
	BITMAP "........"	'$00
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP ".#......"	'$40
	BITMAP "###....."	'$E0
	BITMAP "###....."	'$E0
	BITMAP "........"	'$00

'===Sprite:27 == Chr:283===== [8,8]
'Sprite27:
	BITMAP "........"	'$00
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP "###....."	'$E0
	BITMAP "###....."	'$E0
	BITMAP "........"	'$00

'===Sprite:28 == Chr:284===== [8,8]
'Sprite28:
	BITMAP "########"	'$FF
	BITMAP "#.#.#.##"	'$AB
	BITMAP "#.##.#.#"	'$B5
	BITMAP "#.#.#.##"	'$AB
	BITMAP "#.##.#.#"	'$B5
	BITMAP "#.#.#.##"	'$AB
	BITMAP "#.##.#.#"	'$B5
	BITMAP "########"	'$FF

'===Sprite:29 == Chr:285===== [8,8]
'Sprite29:
	BITMAP ".....#.."	'$04
	BITMAP ".....##."	'$06
	BITMAP ".....###"	'$07
	BITMAP ".....#.#"	'$05
	BITMAP "...###.#"	'$1D
	BITMAP "..####.."	'$3C
	BITMAP "..####.."	'$3C
	BITMAP "...##..."	'$18

'===Sprite:30 == Chr:286===== [8,8]
'Sprite30:
	BITMAP "...#...."	'$10
	BITMAP "..##...."	'$30
	BITMAP ".###...."	'$70
	BITMAP ".#.#...."	'$50
	BITMAP ".#.###.."	'$5C
	BITMAP "...####."	'$1E
	BITMAP "...####."	'$1E
	BITMAP "....##.."	'$0C

'===Sprite:31 == Chr:287===== [8,8]
'Sprite31:
	BITMAP "########"	'$FF
	BITMAP "#.###..#"	'$B9
	BITMAP "#.###..#"	'$B9
	BITMAP "#.###..#"	'$B9
	BITMAP "#.###..#"	'$B9
	BITMAP "...#...#"	'$11
	BITMAP "...#...#"	'$11
	BITMAP "########"	'$FF

'===Sprite:32 == Chr:288===== [8,8]
Sprite32:
	BITMAP "........"	'$00
	BITMAP "....#..."	'$08
	BITMAP "...###.."	'$1C
	BITMAP "..##.##."	'$36
	BITMAP "..##.##."	'$36
	BITMAP ".##...##"	'$63
	BITMAP ".#######"	'$7F
	BITMAP ".##...##"	'$63

'===Sprite:33 == Chr:289===== [8,8]
'Sprite33:
	BITMAP "........"	'$00
	BITMAP ".######."	'$7E
	BITMAP "..##..##"	'$33
	BITMAP "..##..##"	'$33
	BITMAP "..#####."	'$3E
	BITMAP "..##..##"	'$33
	BITMAP "..##..##"	'$33
	BITMAP ".######."	'$7E

'===Sprite:34 == Chr:290===== [8,8]
'Sprite34:
	BITMAP "........"	'$00
	BITMAP "...####."	'$1E
	BITMAP "..##..##"	'$33
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP "..##..##"	'$33
	BITMAP "...####."	'$1E

'===Sprite:35 == Chr:291===== [8,8]
'Sprite35:
	BITMAP "........"	'$00
	BITMAP ".#####.."	'$7C
	BITMAP "..##.##."	'$36
	BITMAP "..##..##"	'$33
	BITMAP "..##...#"	'$31
	BITMAP "..##..##"	'$33
	BITMAP "..##.##."	'$36
	BITMAP ".#####.."	'$7C

'===Sprite:36 == Chr:292===== [8,8]
'Sprite36:
	BITMAP "........"	'$00
	BITMAP ".#######"	'$7F
	BITMAP "..##..##"	'$33
	BITMAP "..##.#.#"	'$35
	BITMAP "..####.."	'$3C
	BITMAP "..##.#.#"	'$35
	BITMAP "..##..##"	'$33
	BITMAP ".#######"	'$7F

'===Sprite:37 == Chr:293===== [8,8]
'Sprite37:
	BITMAP "........"	'$00
	BITMAP ".#######"	'$7F
	BITMAP "..##..##"	'$33
	BITMAP "..##.#.#"	'$35
	BITMAP "..####.."	'$3C
	BITMAP "..##.#.."	'$34
	BITMAP "..##...."	'$30
	BITMAP ".####..."	'$78

'===Sprite:38 == Chr:294===== [8,8]
'Sprite38:
	BITMAP "........"	'$00
	BITMAP "...####."	'$1E
	BITMAP "..##..##"	'$33
	BITMAP ".##....."	'$60
	BITMAP ".##.####"	'$6F
	BITMAP ".##...##"	'$63
	BITMAP "..##.###"	'$37
	BITMAP "...###.#"	'$1D

'===Sprite:39 == Chr:295===== [8,8]
'Sprite39:
	BITMAP "....#..."	'$08
	BITMAP "..#.##.."	'$2C
	BITMAP "..###..."	'$38
	BITMAP ".##.##.."	'$6C
	BITMAP "..###..."	'$38
	BITMAP ".##.#..."	'$68
	BITMAP "..#....."	'$20
	BITMAP "........"	'$00

'===Sprite:40 == Chr:296===== [8,8]
'Sprite40:
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF
	BITMAP "########"	'$FF

'===Sprite:41 == Chr:297===== [8,8]
'Sprite41:
	BITMAP ".#.#.#.#"	'$55
	BITMAP "#.#.#.#."	'$AA
	BITMAP ".#.#.#.#"	'$55
	BITMAP "#.#.#.#."	'$AA
	BITMAP ".#.#.#.#"	'$55
	BITMAP "#.#.#.#."	'$AA
	BITMAP ".#.#.#.#"	'$55
	BITMAP "#.#.#.#."	'$AA

'===Sprite:42 == Chr:298===== [8,8]
'Sprite42:
	BITMAP "#......#"	'$81
	BITMAP "#..##..#"	'$99
	BITMAP "#......#"	'$81
	BITMAP "#..##..#"	'$99
	BITMAP "#......#"	'$81
	BITMAP "#..##..#"	'$99
	BITMAP "#......#"	'$81
	BITMAP "#..##..#"	'$99

'===Sprite:43 == Chr:299===== [8,8]
'Sprite43:
	BITMAP "........"	'$00
	BITMAP ".#..#..#"	'$49
	BITMAP "........"	'$00
	BITMAP ".#..#..#"	'$49
	BITMAP "........"	'$00
	BITMAP ".#..#..#"	'$49
	BITMAP "........"	'$00
	BITMAP ".#..#..#"	'$49

'===Sprite:44 == Chr:300===== [8,8]
'Sprite44:
	BITMAP "........"	'$00
	BITMAP "##...#.."	'$C4
	BITMAP "#....#.."	'$84
	BITMAP "##.#.##."	'$D6
	BITMAP "#.#.##.."	'$AC
	BITMAP "###.#.#."	'$EA
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:45 == Chr:301===== [8,8]
'Sprite45:
	BITMAP "........"	'$00
	BITMAP ".#.#...."	'$50
	BITMAP "#..#...."	'$90
	BITMAP "#..#.##."	'$96
	BITMAP "#..#.#.."	'$94
	BITMAP ".#.#.#.."	'$54
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:46 == Chr:302===== [8,8]
'Sprite46:
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "##.##..."	'$D8
	BITMAP "##.##..."	'$D8
	BITMAP "##.##..."	'$D8
	BITMAP ".###...."	'$70
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:47 == Chr:303===== [8,8]
'Sprite47:
	BITMAP "........"	'$00
	BITMAP ".##....."	'$60
	BITMAP "###....."	'$E0
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP "####...."	'$F0
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:48 == Chr:304===== [8,8]
Sprite48:
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "#..##..."	'$98
	BITMAP "..##...."	'$30
	BITMAP ".##....."	'$60
	BITMAP "#####..."	'$F8
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:49 == Chr:305===== [8,8]
'Sprite49:
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "#..##..."	'$98
	BITMAP "..##...."	'$30
	BITMAP "#..##..."	'$98
	BITMAP ".###...."	'$70
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:50 == Chr:306===== [8,8]
'Sprite50:
	BITMAP "........"	'$00
	BITMAP ".#.##..."	'$58
	BITMAP "##.##..."	'$D8
	BITMAP "#####..."	'$F8
	BITMAP "...##..."	'$18
	BITMAP "...##..."	'$18
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:51 == Chr:307===== [8,8]
'Sprite51:
	BITMAP "........"	'$00
	BITMAP "#####..."	'$F8
	BITMAP "##......"	'$C0
	BITMAP ".###...."	'$70
	BITMAP "#..##..."	'$98
	BITMAP ".###...."	'$70
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:52 == Chr:308===== [8,8]
'Sprite52:
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "##..#..."	'$C8
	BITMAP "####...."	'$F0
	BITMAP "##.##..."	'$D8
	BITMAP ".###...."	'$70
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:53 == Chr:309===== [8,8]
'Sprite53:
	BITMAP "........"	'$00
	BITMAP "#####..."	'$F8
	BITMAP "#..##..."	'$98
	BITMAP "..##...."	'$30
	BITMAP ".##....."	'$60
	BITMAP ".##....."	'$60
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:54 == Chr:310===== [8,8]
'Sprite54:
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "##.##..."	'$D8
	BITMAP ".###...."	'$70
	BITMAP "##.##..."	'$D8
	BITMAP ".###...."	'$70
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'===Sprite:55 == Chr:311===== [8,8]
'Sprite55:
	BITMAP "........"	'$00
	BITMAP ".###...."	'$70
	BITMAP "##.##..."	'$D8
	BITMAP ".####..."	'$78
	BITMAP "#..##..."	'$98
	BITMAP ".###...."	'$70
	BITMAP "........"	'$00
	BITMAP "........"	'$00

'//Total of 56 characters.
'EOF
