

'Draw initial screen... otherwise it will flicker badly, especially fanfold
IntyMusicInit: PROCEDURE

	iMusicX=0	
	WAIT		
	'--draw a bit of the staff	
	FOR #x=0 TO 3*20
		#BACKTAB(#x)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
		iMusicX=iMusicX+1:IF iMusicX>19 THEN iMusicX=0
	NEXT #x
	
	'---Alternate colors
	IF INTYMUSIC_FANFOLD THEN
		iMusicX=0
		FOR #x=1 TO 11
			#BACKTAB(iMusicX)=CS_ADVANCE			
			iMusicX=iMusicX+20
		NEXT #x
	END IF
	
	'Draw &
	PRINT AT 9 COLOR 0,"\277\269\272\261"
	PRINT AT 29,"\278\270\273\262"
	
	'draw )
	PRINT AT 5,"\271\263"
	PRINT AT 25,"\273\262"
	PRINT AT 46,"\279"
	
	PRINT AT 60 COLOR CS_BLUE,"\285"
	PRINT COLOR CS_BLACK," IntyMusic Player "
	PRINT COLOR CS_BLUE,"\285"
	PRINT COLOR CS_BLACK,"by Marco A. Marrero "

	'---------------- ADD YOUR INFORMATION HERE -------------------------
	PRINT AT 120,""
	'-----------------------------------------------------------------
	
	
	PRINT AT 220,"Press button to play"		
	GOSUB WaitForKeyDownThenUp	
RETURN
END

WaitForKeyDownThenUp: procedure
	' Wait for a key to be pressed.
	do while cont=0
		wait
	loop	
	' Wait for a key to be released.
	do while cont<>0
		wait
	loop	
end
