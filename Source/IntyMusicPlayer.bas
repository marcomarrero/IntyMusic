'IntyMusic by Marco A. Marrero.
'IntyMusic_Player.bas | Main code.
'Public domain, feel free to use/modify. Feel free to contact me in the Intellivision Programming forum @ AtariAge.com

WAIT
DEFINE 0,16,Sprite0:WAIT
DEFINE 16,16,Sprite16:WAIT
DEFINE 32,16,Sprite32:WAIT
DEFINE 48,8,Sprite48:WAIT

'--- variables to copy values from IntyBasic_epilogue -----
DIM iMusicNote(3)			'Notes 0,1,2	(from IntyBasic_epilogue)
DIM iMusicVol(3)			'Volume (from IntyBasic_epilogue)
DIM iMusicWaveForm(3)		'Waveform. Will hit 1 for new notes.
DIM iMusicTime(3)			'Counters, from IntyBasic_epilogue: _music_tc - 1 (time base) _music_t (note count), and _music_frame (1=skipped a frame on ntsc)

DIM iMusicNoteLast(3)		'Previous notes
DIM iMusicVolumeLast(3)	'store last volume values
DIM iMusicDrawNote(3)		'Draw new note?

IF INTYMUSIC_FANFOLD THEN #IntyMusicBlink=CS_ADVANCE ELSE #IntyMusicBlink=0

'---------------
IntyMusicReset:

'----show title screen and credits--- also prints vertical song name ---
GOSUB IntyMusicInit

'-----init----
iMusicScroll=0			'Need to scroll screen?
iMusicScrollCount=0		'Scroll counter
Toggle=1					'Piano hilite index, 0 or 1 (Ill XOR it later)
KeyClear=0


'--Volume graph display----
CONST CharVolume = (iMusic_VolumeCard*8) + 2048		'GRAM card 40, 41 or 43 for volume bar. I prefer 43.
CONST NotePosition = 96+ZOOMY2+13

'--- PLAY! -----
WAIT
PLAY MyMusic

'---- main loop -----
PlayLoop:
	WAIT 
	
	'--- The iMusicScroll is modified in a ON FRAME GOSUB... code at the end of this file ---
	IF iMusicScroll<>0 THEN	
		CALL MUSICSCROLL		'Scroll... I am only moving part of the screen to avoid redrawing
		iMusicScroll=0
		
		'---Alternate colors---
		#BACKTAB(0)=#IntyMusicBlink:#BACKTAB(220)=#IntyMusicBlink			
		PRINT AT 221		'<--- Do NOT remove! 	
		
		'---Draw letter, C3# A4 B5-----	
		FOR iMusicX=0 TO 2
			IntyNote=iMusicNote(iMusicX)	'Get note value to use in look-up tables 
			#x=iMusicNoteColor(iMusicX)	'Get note color
							
			PRINT 2280+iMusicDrawNote(iMusicX)	'Note + blink	'Print "\285" (2280=285*8)
			
			'Note text,ex. C5#
			'PRINT IntyNoteLetter(IntyNote)+#x,IntyNoteSharp(IntyNote)+#x,IntyNoteOctave(IntyNote)+#x Old one
			PRINT CharVolume+#iMusicPianoColorB(iMusicX),IntyNoteLetter(IntyNote)+#x,IntyNoteSharp(IntyNote)+#x,IntyNoteOctave(IntyNote)+#x,0				
		NEXT iMusicX
			
		'----Done updating lower screen. Clear top line, draw staff---
		FOR iMusicX=1 TO 18
			#BACKTAB(iMusicX)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
		NEXT iMusicX
		
		'---Use sprites to "hilite" piano keys and draw notes-----
		Toggle=Toggle XOR 1	'Toggle piano key hilite, 1 or 0
		FOR iMusicX=0 TO 2
			IntyNote=iMusicNote(iMusicX)	'--Get note 
			
			'---Draw Note. Up to 2 notes per card. I used a spreadsheet to create lookup data, card, position, etc.--
			IF iMusicDrawNote(iMusicX) THEN 
				#BACKTAB(IntyNoteOnscreen(IntyNote))=IntyNoteGRAM(IntyNote) + iMusicNoteColor(iMusicX)				
				iMusicDrawNote(iMusicX)=0
			END IF
			
			'---Overlay sprites on piano keys. Flash colors---
			IF Toggle THEN #x=#iMusicPianoColorA(iMusicX) ELSE #x=#iMusicPianoColorB(iMusicX)				
			IF iMusicVol(iMusicX)=0 THEN
				resetsprite(iMusicX)
			ELSE
				SPRITE iMusicX,16 + VISIBLE + IntyPianoSpriteOffset(IntyNote),88 + ZOOMY2, IntyPianoSprite(IntyNote) + #x
			END IF				
		NEXT iMusicX
	END IF '<--iMusicTime
	
	'---Update volume sprite --- 
	iMusicX=8		'8th char
	FOR #x=0 TO 2
		'Volume meter...
		SPRITE #x+5,16 + VISIBLE + iMusicX,NotePosition-iMusicVol(#x), SPR42 + #iMusicPianoColorA(#x) + BEHIND
		iMusicX=iMusicX+48		
	NEXT #x	
	
	'---- user reset? ----
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

'----------------------------------------------------------------------

'-- New way to synchronize. Now I am sure I am not skipping any frame in any way
'-- This is called at every frame, I skip every 6th frame ---
DoStuffAfterWait: PROCEDURE	

	IF MUSIC.PLAYING<>0 THEN
		'--Get music player values from IntyBasic_epilogue ASM
		CALL IMUSICGETINFOV2(VARPTR iMusicVol(0), VARPTR iMusicNote(0), VARPTR iMusicWaveForm(0),VARPTR iMusicTime(0))
				
		'Check values if frame was not skipped (every 6 frames on NTSC)
		IF iMusicTime(2)<>1 THEN
			
			'--Force scrolling according to INTYMUSIC_NEW_AUTO_SCROLL. 0=pause between notes (or wait 256 frames), 1=scroll at every frame, 2=skip one frame, etc.
			'--- On any note change screen will scroll, and this value gets reset.
			iMusicScrollCount=iMusicScrollCount+1
			IF iMusicScrollCount=INTYMUSIC_NEW_AUTO_SCROLL THEN iMusicScrollCount=0:iMusicScroll=1
			
			'--- check if new note played, or if waveform index changed (same note was hit again)---
			FOR #AfterWait=0 TO 2
				IF iMusicNoteLast(#AfterWait)<>iMusicNote(#AfterWait) THEN 
					iMusicNoteLast(#AfterWait)=iMusicNote(#AfterWait)
					iMusicDrawNote(#AfterWait)=iMusicNoteColor(#AfterWait)
					iMusicScroll=1
					iMusicScrollCount=0
					
				ELSEIF iMusicWaveForm(#AfterWait)=1 THEN
					iMusicDrawNote(#AfterWait)=iMusicNoteColor(#AfterWait)
					iMusicScroll=1
					iMusicScrollCount=0
				END IF
			NEXT #AfterWait	
		END IF 'iMusicTime
	END IF	
END
