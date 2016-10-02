'IntyMusic Playlist Menu. Will return result in variable "iMusicSelection", 1=song1, etc.

IntyMusic_PlayList_Menu: PROCEDURE
ResetList:
	PageMax = 3				'<-- Total Pages: 0,1,2
	PageLastEntry=18		'Options 1 to 18 are valid
	PageNumber=0
	iMusicScroll=0
	
	'----Draw menu-----
PickAgain:		
	WAIT:CLS:GOSUB DrawMainScreen:GOSUB DrawFanFoldBorder	
	'---Write 0 blank--
	#x=238
	#BACKTAB(#x)= "0" * 8
	#BACKTAB(#x+1)=0	
	
	ON PageNumber GOTO Page0, Page1, Page2, Page3
		
'---------------
Page0:
	PRINT AT  81,"1.2 Part invent. A-"	
	PRINT AT 101,"2.2 Part invent. Bb"
	PRINT AT 121,"3.Final Fantasy 1"
	PRINT AT 141,"4.Kenseiden Round 3"
	PRINT AT 161,"5.Lord of the Sword"
	GOTO PageInput

'---------------	
Page1:
	PRINT AT  81,"6.Mozart Kyrie Req"
	PRINT AT 101,"7.Space Harrier C64"
	PRINT AT 121,"8.SuperMario Bros 2"
	PRINT AT 141,"9.Typewriter Song"
	PRINT AT 161,"10.**Chopin"
GOTO PageInput
	
'---------------
Page2:
	PRINT AT  81,"11.**FF2 World"
	PRINT AT 101,"12.**Piano Son C"
	PRINT AT 121,"13.**Rastan End"
	PRINT AT 141,"14.**Teddy Boy"
	PRINT AT 161,"15.**Truxton Boss"	    
GOTO PageInput	

Page3:
	PRINT AT  81,"16.**WnderB DTrap"
	PRINT AT 101,"17.**Book2 PreludF"	
	PRINT AT 121,"18.**Wizball ST"
	'PRINT AT 121,"19."
	'PRINT AT 141,"20."
	'GOTO PageInput
	
'---------------
PageInput:	
	IntyNote=152	
	ButtonClear=0:KeyClear=0
	iMusicX=10:iMusicScroll=8
	Toggle=0

PageInputLoop:
	WAIT
	iMusicX=iMusicX+1
	IF iMusicX>10 THEN 
		iMusicX=0:iMusicScroll=iMusicScroll+1
		IF iMusicScroll>8 THEN 
			iMusicScroll=0
			Toggle=Toggle+1
			IF Toggle=1 THEN 
				PRINT AT 219:PRINT COLOR FG_BLUE,0,CS_ADVANCE,"Key # then Enter:"
			ELSEIF Toggle=4 THEN 
			   PRINT AT 219:PRINT COLOR FG_BLACK,0,CS_ADVANCE,"Hit Clr top page:"
			ELSEIF Toggle=7 THEN
				PRINT AT 219:PRINT COLOR FG_DARKGREEN,0,CS_ADVANCE,"Buttons: Up/Down:"
			ELSEIF Toggle >9 THEN
				Toggle=0
			END IF
		END IF
	END IF
	
	SPRITE 0,IntyNote + VISIBLE, 102 + ZOOMY2, SPR40 + BEHIND + iMusicScroll

	IF Cont.KEY=12 THEN 
		KeyClear=1
	ELSE
		IF KeyClear THEN								
			IF Cont.KEY=10 THEN GOTO ResetList		'--- Clr=Delete input ----			
			IF Cont.KEY=11 THEN GOTO InputNum		'--- Enter=Pick ----
			
			'--just write a number on BACKTAB. I will fetch it later
			#BACKTAB(#x)= (16 + Cont.KEY) * 8
			IF #x=238 THEN
				#x=#x+1:IntyNote=160
			ELSE
				#x=#x-1:IntyNote=152
			END IF	
		END IF
		KeyClear=0
	END IF 
		
	'-- Test triggers for page down, page up.. 
	IF CONT.B0 THEN '---Page up
		IF ButtonClear THEN
			IF PageNumber=0 THEN PageNumber=PageMax ELSE PageNumber=PageNumber-1
			ButtonClear=0
			GOTO PickAgain
		END IF
		
	ELSEIF CONT.B1  OR CONT.B2 THEN '---Page down
		IF ButtonClear THEN
			PageNumber=PageNumber+1:IF PageNumber>PageMax THEN PageNumber=0
			ButtonClear=0
			GOTO PickAgain
		END IF
	ELSE
		ButtonClear=1
	END IF					
	GOTO PageInputLoop	
	
InputNum:
	'-convert chars to decimal, validate, exit if valid
	iMusicSelection=((#BACKTAB(238)/8)-"0")	'Read digit
	IF #BACKTAB(239)<>0 THEN 				'If there is no right digit, it is 0-9
		iMusicSelection= (iMusicSelection*10) + ((#BACKTAB(239)/8)-"0")
	END IF
	
	'---do not exit if it is out of range 
	IF iMusicSelection=0 OR iMusicSelection>PageLastEntry THEN GOTO PageInputLoop
	ResetSprite(0)
END

'----------
