'IntyMusic by Marco A. Marrero.  Started at 7-30-2016, version 7/31/2016
INCLUDE "constants.bas"

'-----OPTIONS------
CONST INTYMUSIC_STAFF_COLOR = FG_BLUE		'FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
CONST INTYMUSIC_AUTO_SCROLL = 1			'0 to pause at notes, 1 to always scroll
CONST INTYMUSIC_FANFOLD = 1				'1 to alternate colors, like classic dot-matrix fanfold paper

CONST INTYMUSIC_PIANO_HILITE1 = SPR_CYAN	'Piano hilite: (SPR_*: BLACK,BLUE,RED,TAN,DARKGREEN,GREEN,YELLOW,WHITE,GREY,CYAN,ORANGE,BROWN,PINK,LIGHTBLUE,YELLOWGREEN,PURPLE)
CONST INTYMUSIC_PIANO_HILITE2 = SPR_YELLOWGREEN
PLAY FULL
'-----Required------

	
INCLUDE "IntyMusicPlayer.bas"
INCLUDE "IntyMusicCredits.bas"		'<--- change this if you want to change initial screen
INCLUDE "IntyMusicGraphics.bas"
INCLUDE "IntyMusicData.bas"

'-----Music to use------
'MyMusic:
asm org $A000
INCLUDE "requiem.bas"	 '<---- Music data. Data label *must* be named "MyMusic"
