'IntyMusic by Marco A. Marrero.  Started at 7-30-2016, version 8/9/2016

'----Required----
INCLUDE "constants.bas"
PLAY FULL
DIM iMusicNoteColor(3)		'Note color 
DIM #iMusicPianoColorA(3)
DIM #iMusicPianoColorB(3)

'========================== Options you can modify =============================================
CONST INTYMUSIC_STAFF_COLOR = FG_BLUE		'FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
CONST INTYMUSIC_AUTO_SCROLL = 1			'0 to pause at notes, 1 to always scroll
CONST INTYMUSIC_FANFOLD = 1				'1 to alternate colors, like classic dot-matrix paper
CONST INTYMUSIC_TITLE_COLOR=FG_BLUE			'---Song title Color ---- FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE

'--- Note color, by voice channel ---- FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
iMusicNoteColor(0)=FG_BLACK
iMusicNoteColor(1)=FG_RED
iMusicNoteColor(2)=SPR_DARKGREEN

'--- Piano key color, by voice channel ---- 2nd set for flash effect. Use same colors on 2nd set to disable blink
' SPR_BLACK,SPR_BLUE,SPR_RED,SPR_TAN,SPR_DARKGREEN,SPR_GREEN,SPR_YELLOW,SPR_WHITE,SPR_GREY,SPR_CYAN,SPR_ORANGE,SPR_BROWN,SPR_PINK,SPR_LIGHTBLUE,SPR_YELLOWGREEN,SPR_PURPLE			7
#iMusicPianoColorA(0)=SPR_BLACK
#iMusicPianoColorA(1)=SPR_RED
#iMusicPianoColorA(2)=SPR_DARKGREEN

#iMusicPianoColorB(0)=SPR_GREY
#iMusicPianoColorB(1)=SPR_ORANGE
#iMusicPianoColorB(2)=SPR_GREEN

'Alternating colors: STACK_BLACK,STACK_BLUE,STACK_RED,STACK_TAN,STACK_DARKGREEN,STACK_GREEN,STACK_YELLOW,STACK_WHITE,STACK_GREY,STACK_CYAN,STACK_ORANGE,STACK_BROWN,STACK_PINK,STACK_LIGHTBLUE,STACK_YELLOWGREEN,STACK_PURPLE
MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
'MODE 0,STACK_GREY,STACK_LIGHTBLUE,STACK_WHITE,STACK_CYAN

'========================== Options End =============================================

'-----Required------ 
INCLUDE "IntyMusicPlayer.bas"
INCLUDE "IntyMusicCredits.bas"		
INCLUDE "IntyMusicGraphics.bas"
INCLUDE "IntyMusicData.bas"

'========== More Options =======================
IntyMusicInit_Credits: PROCEDURE
	'---------------- ADD INFORMATION BELOW -------------------------
	PRINT AT 120,"Song:Space Harrier"   	'<
	'GOSUB Print_Song_Name					'<-- use the same text from vertical print
	
	PRINT AT 140,"From:C64 Hi-Score"
	PRINT AT 160,"  By:Mark Cooksey"
	'-----------------------------------------------------------------
RETURN
END	

'-----Music to use------
'MyMusic:
asm org $A000
INCLUDE "Songs\SHarrierC64.bas"		 '<---- Music data. Data label *must* be named "MyMusic"

'--- song name ------ Must be 12 characters or less! -----
MyMusicName:
DATA "SHarrier C64"
REM "123456789012"

'----dont remove----
DATA 0,0,0,0,0,0,0,0,0,0,0,0
