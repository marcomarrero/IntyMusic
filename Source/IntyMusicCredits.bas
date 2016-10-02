'Draw credits/title screen

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

