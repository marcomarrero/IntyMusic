'IntyMusic by Marco A. Marrero.  Started at 7-30-2016, version 8/10/2016

'----Required----
INCLUDE "constants.bas"
PLAY FULL
DIM iMusicNoteColor(3)		'Note color 
DIM #iMusicPianoColorA(3)
DIM #iMusicPianoColorB(3)

'========================== Options #1 - customization ========================================
CONST INTYMUSIC_AUTO_SCROLL = 1			'0 to pause at notes, 1 to always scroll
CONST INTYMUSIC_FANFOLD = 1				'1 to alternate colors, like classic dot-matrix paper

'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
CONST INTYMUSIC_STAFF_COLOR = FG_BLACK		'-- staff color 
CONST INTYMUSIC_TITLE_COLOR=FG_BLUE			'---Song title Color

'--- Music note color, by voice channel (drawn on top, scrolls down)----
iMusicNoteColor(0)=FG_DARKGREEN
iMusicNoteColor(1)=FG_RED
iMusicNoteColor(2)=FG_BLUE

'--- Piano key color, by voice channel ---- 2nd set for flash effect. Use same colors on 2nd set to disable blink
' SPR_BLACK,SPR_BLUE,SPR_RED,SPR_TAN,SPR_DARKGREEN,SPR_GREEN,SPR_YELLOW,SPR_WHITE,SPR_GREY,SPR_CYAN,SPR_ORANGE,SPR_BROWN,SPR_PINK,SPR_LIGHTBLUE,SPR_YELLOWGREEN,SPR_PURPLE			7
'--1st set---
#iMusicPianoColorA(0)=SPR_DARKGREEN
#iMusicPianoColorA(1)=SPR_RED
#iMusicPianoColorA(2)=SPR_BLUE
'--2nd set, flash---
#iMusicPianoColorB(0)=SPR_GREEN
#iMusicPianoColorB(1)=SPR_ORANGE
#iMusicPianoColorB(2)=SPR_LIGHTBLUE

'----Color stack----alternating background colors 
'STACK_BLACK,STACK_BLUE,STACK_RED,STACK_TAN,STACK_DARKGREEN,STACK_GREEN,STACK_YELLOW,STACK_WHITE,STACK_GREY,STACK_CYAN,STACK_ORANGE,STACK_BROWN,STACK_PINK,STACK_LIGHTBLUE,STACK_YELLOWGREEN,STACK_PURPLE
BORDER BORDER_WHITE,0
MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
'MODE 0,STACK_GREY,STACK_LIGHTBLUE,STACK_WHITE,STACK_CYAN

CONST INTYMUSIC_SONG_TITLE = 1		'0 to disable song title, should eliminate flicker 

'========================== Options #1 End =============================================

'-----Required------ 
INCLUDE "IntyMusicPlayer.bas"
INCLUDE "IntyMusicCredits.bas"		
INCLUDE "IntyMusicData.bas"
INCLUDE "IntyMusicGraphics.bas"

'========================== Options #2 - More customization ========================================

IntyMusicInit_Credits: PROCEDURE
	'---------------- ADD INFORMATION BELOW -------------------------
	'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
	PRINT COLOR FG_DARKGREEN
	'20 char max 1234567890123456789
	PRINT AT 060," "	
	
	PRINT COLOR FG_GREEN
	PRINT AT 080,"Tchaikovsky 1812"	
	PRINT AT 100,"   "	
	PRINT AT 120," "
	'-----------------------------------------------------------------
END	

'-----Music to use------
'MyMusic:
asm org $A000
INCLUDE "tchaikovsky1812.bas"		 '<---- Music data. Data label *must* be named "MyMusic"

'--- song name, printed vertically --- Must be 12 characters or less! -----
MyMusicName:
DATA "     Demo"
REM "123456789012"
'--- To disable this text, change this above: CONST INTYMUSIC_SONG_TITLE = 0 

'======= Options #2 End =======
''NOTE: If Music speed is 1, IntyMusic will not scroll, change the following in IntyMusicPlayer.bas:
''IF #iMusicTime(1)=#iMusicTime(0) THEN	 ---change to----> IF #iMusicTime(1)=1 THEN	

DATA 0,0,0,0,0,0,0,0,0,0,0,0
