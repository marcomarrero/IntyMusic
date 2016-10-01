'IntyMusic by Marco A. Marrero.  Started at 7/30/2016, v8/10/2016, big revision: v10/1/2016

'----Required----
ON FRAME GOSUB DoStuffAfterWait
INCLUDE "constants.bas"
PLAY FULL
DIM iMusicNoteColor(3)		'Note color 
DIM #iMusicPianoColorA(3)
DIM #iMusicPianoColorB(3)

'========================== Options #1 - customization ========================================
INTYMUSIC_NEW_AUTO_SCROLL = 5		'--- 0=scroll only when any note changes, 1=scroll every frame (fast!), 2=skip one frame, 3=skip 2, etc.
								'---- Large numbers will not freeze player, it always scrolls when any note plays and resets count to 0
								'---- In previous versions, it was 1 or 0. Use 4 or 5 on this version instead
								'---- It's a variable now, if you have multiple songs can be changed in runtime

CONST INTYMUSIC_FANFOLD = 1	'1 for alternating colors, like classic dot-matrix paper

'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
CONST INTYMUSIC_STAFF_COLOR= FG_BLACK		'-- staff color 
CONST INTYMUSIC_TITLE_COLOR=FG_BLUE			'---Song title Color

'--- Music note color, by voice channel (drawn on top, scrolls down)----
iMusicNoteColor(0)=FG_DARKGREEN
iMusicNoteColor(1)=FG_RED
iMusicNoteColor(2)=FG_BLUE

'--- Piano key and Volume colors, by voice channel -- 2nd set flash effect. Use same colors on 2nd to disable hilite/blink
' SPR_BLACK,SPR_BLUE,SPR_RED,SPR_TAN,SPR_DARKGREEN,SPR_GREEN,SPR_YELLOW,SPR_WHITE,SPR_GREY,SPR_CYAN,SPR_ORANGE,SPR_BROWN,SPR_PINK,SPR_LIGHTBLUE,SPR_YELLOWGREEN,SPR_PURPLE			7
'--1st set---
#iMusicPianoColorA(0)=SPR_DARKGREEN
#iMusicPianoColorA(1)=SPR_RED
#iMusicPianoColorA(2)=SPR_BLUE
'--2nd set, flash---
#iMusicPianoColorB(0)=SPR_GREEN
#iMusicPianoColorB(1)=SPR_ORANGE
#iMusicPianoColorB(2)=SPR_LIGHTBLUE

'--- volume bar on each sound channel---
CONST iMusic_VolumeCard = 43	'GRAM cards 40, 41 or 43 are for back of volume bar. I prefer 43. Card 42 voids it, Other values are valid, like 29

'----Color stack----alternating background colors 
'STACK_BLACK,STACK_BLUE,STACK_RED,STACK_TAN,STACK_DARKGREEN,STACK_GREEN,STACK_YELLOW,STACK_WHITE
'STACK_GREY,STACK_CYAN,STACK_ORANGE,STACK_BROWN,STACK_PINK,STACK_LIGHTBLUE,STACK_YELLOWGREEN,STACK_PURPLE
BORDER BORDER_WHITE,0
MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
'MODE 0,STACK_GREY,STACK_LIGHTBLUE,STACK_WHITE,STACK_GREEN
'MODE 0,STACK_YELLOWGREEN,STACK_DARKGREEN,STACK_WHITE,STACK_GREEN

CONST INTYMUSIC_SONG_TITLE = 1		'0 to disable vertical song title

'========================== Options #1 End =============================================

'-----Required------ 
INCLUDE "IntyMusicPlayer.bas"
INCLUDE "IntyMusicCredits.bas"		
INCLUDE "IntyMusicData.bas"

INCLUDE "IntyMusicGraphics.bas"
INCLUDE "IntyMusicASM.bas"

'========================== Options #2 - More customization ========================================
IntyMusicInit_Credits: PROCEDURE
	'---------------- ADD INFORMATION BELOW -------------------------
	'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
	PRINT COLOR FG_DARKGREEN	
	PRINT AT 060," "	
	'20 char max 1234567890123456789
	PRINT COLOR FG_BLACK
	PRINT AT 080,"Song title goes here"
	PRINT COLOR FG_DARKGREEN
	PRINT AT 100,"Additional text here"
	PRINT COLOR FG_GREEN
	PRINT AT 120,"Extra text goes here"
END	

'--- song name, printed vertically --- Must be 12 characters or less! -----
'--- To disable this text, change this above: CONST INTYMUSIC_SONG_TITLE = 0 
MyMusicName:
DATA "Example Name"
REM "123456789012"
DATA 0,0,0,0,0,0,0,0,0,0,0,0

'=======================================Song to use======================================================
asm ORG $C040		;---big segment for music

'MyMusic:
INCLUDE "songs\SMario2.bas"		 '<---- Music data. Data label *must* be named "MyMusic" (or, do not use label, uncomment above)

'---IntyBasic epilogue------
asm ORG $A000
