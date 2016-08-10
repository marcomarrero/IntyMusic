'IntyMusic by Marco A. Marrero.  Started at 7-30-2016, version 8/3/2016
'IntyMusic_Player.bas | Main code.
'Public domain, feel free to use/modify. Feel free to contact me in the Intellivision Programming forum @ AtariAge.com

'MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
WAIT

BORDER BORDER_WHITE,0
DEFINE 0,16,Sprite0:WAIT
DEFINE 16,16,Sprite16

'--- variables to copy values from IntyBasic_epilogue -----
DIM #iMusicNote(3)		'Notes 0,1,2	(from IntyBasic_epilogue)
DIM #iMusicVol(3)			'Volume (from IntyBasic_epilogue)
DIM #iMusicInst(3)		'Instrument. I need to match volume history...
DIM #iMusicTime(2)		'Time counter (from IntyBasic_epilogue, _music_tc, Time base -1 (_music_t)

DIM iMusicNoteLast(3)		'Previous notes
DIM iMusicVolumeLast(3)	'store last volume values, compare with instrument... sigh...

'---------------
IntyMusicReset:
CLS
resetsprite(0):resetsprite(1):resetsprite(2)	
WAIT

'-----
iMusicScroll=0			'Need to scroll screen?
DIM iMusicDrawNote(3)		'Draw new note?
#x=0
Toggle=1
KeyClear=0
#IntyMusicBlink=0: IF INTYMUSIC_FANFOLD THEN #IntyMusicBlink=CS_ADVANCE

'----initialize---
WAIT
GOSUB IntyMusicInit

'---- main loop -----
PLAY MyMusic
PlayLoop:
	'--I will keep track of notes playing for each voice, and also keep track of volume to know if same note played again
	FOR iMusicX=0 to 2
		iMusicNoteLast(iMusicX)=#iMusicNote(iMusicX)	
		iMusicVolumeLast(iMusicX)=#iMusicVol(iMusicX)
	NEXT iMusicX	
	
	'---- reset? ----
	IF Cont.KEY=12 THEN 
		KeyClear=1
	ELSE
		IF KeyClear THEN 
			IF Cont.KEY=10 THEN 
				PLAY OFF						
				SOUND 0,1,0:	SOUND 1,1,0:	SOUND 2,1,0:SOUND 4,1,$38
				CALL IMUSICKILL	'works too well...
				GOTO IntyMusicReset
			END IF
		END IF
		KeyClear=0
	END IF	
	'-------------------
	
	'--Get values from IntyBasic_epilogue	
	Call IMUSICGETINFO(VARPTR #iMusicVol(0), VARPTR #iMusicNote(0), VARPTR #iMusicTime(0), VARPTR #iMusicInst(0))	
	
	'Use IntyBasic music counter (_music_tc), if its 1 I can check if new notes are playing	
	IF #iMusicTime(1)=#iMusicTime(0) THEN	 'IF Song Speed is 1, player will freeze.. use this code instead: 'IF #iMusicTime(1)=1 THEN	
	
		iMusicScroll=0		
		FOR iMusicX=0 to 2	
			IntyNote=0
			IF iMusicNoteLast(iMusicX)<>#iMusicNote(iMusicX) THEN GOTO GotIntyNote	'note changed
			
			'Same note? check last volume. piano: 14,13 clarinet: 13,14 bass: 12,13 flute:10,12
			iMusicVolCheck=#iMusicVol(iMusicX)
			iMusicVolLast=iMusicVolumeLast(iMusicX)
			iMusicInst=#iMusicInst(iMusicX)
			IF iMusicInst=0 THEN IF iMusicVolLast=14 AND iMusicVolCheck=13 THEN GOTO GotIntyNote	'piano
			IF iMusicInst=64 THEN IF iMusicVolLast=13 AND iMusicVolCheck=14 THEN GOTO GotIntyNote	'clarinet
			IF iMusicInst=128 THEN IF iMusicVolLast=10 AND iMusicVolCheck=12 THEN GOTO GotIntyNote	'flute 
			IF iMusicInst=192 THEN IF iMusicVolLast=12 AND iMusicVolCheck=13 THEN GOTO GotIntyNote	'bass
			GOTO GotIntyNoteFail

		GotIntyNote:			
			IntyNote=1
			
		GotIntyNoteFail:
			iMusicDrawNote(iMusicX)=IntyNote
			iMusicScroll=iMusicScroll+IntyNote
			
		NEXT iMusicX
		
		'---------------- SCROLL, DRAW MUSIC ----------------------------		
		'--- Theres very little time after VBLANK, I had to rearrange things here to draw bottom display first
		IF (INTYMUSIC_AUTO_SCROLL OR iMusicScroll) THEN 			
			Toggle=Toggle XOR 1	'Toggle piano key color
			
			SCROLL 0,0,3			'Scroll upwards (move things down), just about...
			WAIT					'....NOW!
			
			'- Draw piano---
			FOR iMusicX=0 TO 18
				#BACKTAB(200+iMusicX)= IntyPiano(iMusicX)
			NEXT iMusicX	
			
			'---Alternate colors---
			'IF INTYMUSIC_FANFOLD THEN	#BACKTAB(0)=CS_ADVANCE			
			#BACKTAB(0)=#IntyMusicBlink			
			PRINT AT 220, CS_ADVANCE
			'---Draw lower bottom note data-----	
			FOR iMusicX=0 TO 2
				IntyNote=#iMusicNote(iMusicX)	'Get note value to use in look-up tables 
				#x=iMusicNoteColor(iMusicX)	'Get note color
				
				PRINT COLOR #x,2280 + iMusicDrawNote(iMusicX)
				PRINT IntyNoteLetter(IntyNote)+#x,IntyNoteOctave(IntyNote)+#x,IntyNoteSharp(IntyNote)+#x		'Note text,ex. C5#
			NEXT iMusicX
						
			'--Print song name 
			#x=19
			FOR iMusicX=0 TO 11
				#BACKTAB(#x)=MyMusicName(iMusicX)*8 + INTYMUSIC_TITLE_COLOR
				#x=#x+20
			NEXT iMusicX
			
			'---Draw bottom left piano, lefmost key... to avoid erasing other keys that scrolled down. 
			PRINT 2272 'PRINT "\284"
			'----Clear top line, draw staff---
			FOR iMusicX=1 TO 18
				#BACKTAB(iMusicX)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
			NEXT iMusicX
			
			'---Use sprites to "hilite" piano keys and draw notes-----
			FOR iMusicX=0 TO 2
				IntyNote=#iMusicNote(iMusicX)	'--Get note 
				
				'Draw Note
				IF iMusicDrawNote(iMusicX) THEN #BACKTAB(IntyNoteOnscreen(IntyNote))=IntyNoteGRAM(IntyNote) + iMusicNoteColor(iMusicX)				
				
				'Overlay sprites on piano keys. Flash colors 
				IF Toggle THEN #x=#iMusicPianoColorA(iMusicX) ELSE #x=#iMusicPianoColorB(iMusicX)
				SPRITE iMusicX,16 + VISIBLE + IntyPianoSpriteOffset(IntyNote),88 + ZOOMY2, IntyPianoSprite(IntyNote) + #x
			NEXT iMusicX		
		END IF '<----- Scroll			
	ELSE	
		WAIT
	END IF '<-----#iMusicTime()
GOTO PlayLoop

'--Prints song name, after last PRINT position
Print_Song_Name: PROCEDURE
	FOR iMusicX=0 TO 11
		#BACKTAB(iMusicX+POS(0))=MyMusicName(iMusicX)*8 + INTYMUSIC_TITLE_COLOR
	NEXT iMusicX
RETURN
END
'    _______________
'___/ IMUSICGETINFO \________________________________________________________________
'Get IntyBasic_epilogue data onto IntyBasic. Ill copy note and volume
'Call IMUSICGETINFO(VARPTR #iMusicVol(0), VARPTR #iMusicNote(0), VARPTR #iMusicTime(0), VARPTR #iMusicInst(0))	
ASM IMUSICGETINFO: PROC	
'r0 = 1st parameter, VARPTR #iMusicVol(0)
'r1 = 2nd parameter, VARPTR #iMusicNote(0)
'r2 = 3rd parameter, VARPTR #iMusicTime(0)
'r3 = 4rd parameter, VARPTR #iInstrument(0)
'asm pshr r5				;push return
		
'--- Get iIntruments ---------
	asm movr	r3,r4				; r3 --> r4 		
	asm mvi _music_i1,r3
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi _music_i2,r3
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi _music_i3,r3
	asm mvo@ r3,r4				; r3 --> [r4++]

'---- get volume, to know when same note played again ---
	asm movr	r0,r4			;r0 --> r4 (r4=r0=&#iMusicVol(0))
	
	asm mvi	_music_vol1,r3	;  --> r3	
	asm mvo@ r3,r4			;r2 --> [r4++]
	asm mvi	_music_vol2,r3	; --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_vol3,r3	; --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
		
'--- get notes ---
	asm movr	r1,r4			;r1 --> r4. (r4=&#iMusicNote(0))
	asm mvi	_music_n1,r3		;_music_n1 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_n2,r3 	;_music_n2 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_n3,r3		;_music_n3 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	
'--- get time counter and time base --------
	asm movr r2,r4				;r2 --> r4  (r4= &#iMusicTime(0))
	asm mvi _music_t,r3			; _music_t --> r3 (time base)
	asm decr r3 					; r3--
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi	_music_tc,r3			; _music_t --> r3 (time)	
	asm mvo@ r3,r4				; r3 --> [r4++]

'-------------------------------------------------------------	
	asm jr	r5				;return 
	
	'asm	pulr pc				;return 
	'asm mvi@ r3,r3				; Get pointer, r3=[r3] 
	'asm xorr	r3,r3 			; r3=0
asm ENDP

'    ____________
'___/ IMUSICKILL \________________________________________________________________
'PLAY NONE seems not to work....
ASM IMUSICKILL: PROC	
		
'--- kill notes ---
	asm xorr r0,r0			;clear r0
	asm mvo	r0,_music_n1
	asm mvo	r0,_music_n2
	asm mvo 	r0,_music_n3
	asm jr	r5				;return 
asm ENDP


'============================================================================================================
'From IntyBasic_epilogue.asm
'_music_table:	RMB 1	; Note table
'_music_start:	RMB 1	; Start of music
'_music_p:	RMB 1	; Pointer to music
'- - - - - - -
'_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
'_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
'_music_tc:  RMB 1       ; Time counter
'_music_t:   RMB 1       ; Time base
'_music_i1:  RMB 1       ; Instrument 1 
'_music_s1:  RMB 1       ; Sample pointer 1
'_music_n1:  RMB 1       ; Note 1
'_music_i2:  RMB 1       ; Instrument 2
'_music_s2:  RMB 1       ; Sample pointer 2
'_music_n2:  RMB 1       ; Note 2
'_music_i3:  RMB 1       ; Instrument 3
'_music_s3:  RMB 1       ; Sample pointer 3
'_music_n3:  RMB 1       ; Note 3
'_music_s4:  RMB 1       ; Sample pointer 4
'_music_n4:  RMB 1       ; Note 4 (really it's drum)
'-----
'_music_freq10:	RMB 1   ; Low byte frequency A
'_music_freq20:	RMB 1   ; Low byte frequency B
'_music_freq30:	RMB 1   ; Low byte frequency C
'_music_freq11:	RMB 1   ; High byte frequency A
'_music_freq21:	RMB 1   ; High byte frequency B
'_music_freq31:	RMB 1   ; High byte frequency C
'_music_mix:	RMB 1   ; Mixer
'_music_noise:	RMB 1   ; Noise
'_music_vol1:	RMB 1   ; Volume A
'_music_vol2:	RMB 1   ; Volume B
'_music_vol3:	RMB 1   ; Volume C
'_music_vol:	RMB 1	; Global music volume


'--- get volume, to know if note just started to play ---
'	asm movr	r0,r4			;r0 --> r4 (r4=r0=#iMusicVol)
'	asm mvi	_music_vol1,r3	;_music_vol1 --> r3
'	'asm mvi	_music_s1,r3		; --> r3
'	asm mvo@ r3,r4			;r3 --> [r4++]
'	
'	asm mvi	_music_vol2,r3	;_music_vol2 --> r3
'	'asm mvi	_music_s2,r3		; --> r3
'	asm mvo@ r3,r4			;r3 --> [r4++]
'
'	asm mvi	_music_vol3,r3	;_music_vol3 --> r3
'	'asm mvi	_music_s3,r3		; --> r3
'	asm mvo@ r3,r4			;r3 --> [r4++]
