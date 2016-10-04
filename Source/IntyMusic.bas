'IntyMusic by Marco A. Marrero.  Started at 7/30/2016, v8/10/2016, big revision: v10/3/2016

'----Required----
ON FRAME GOSUB DoStuffAfterWait
INCLUDE "constants.bas"		'<-- if not found, copy file from IntyBasic folder to the IntyMusic folder

PLAY FULL
DIM iMusicNoteColor(3)		'Note color 
DIM #iMusicPianoColorA(3)
DIM #iMusicPianoColorB(3)

'========================== Options #1 - customization ========================================
INTYMUSIC_PLAY_VOLUME = 15		'--- PLAY VOLUME. 0=silence, 15=maximum. Also used by Volume meter

INTYMUSIC_NEW_AUTO_SCROLL = 5	'--- 0=scroll only when any note changes, 1=scroll every frame (fast!), 2=skip one frame, 3=skip 2, etc.
							'---- Large numbers will not freeze player, it always scrolls when any note plays and resets count to 0
							'---- In previous versions, it was 1 or 0. Use 4 or 5 on this version instead

INTYMUSIC_FANFOLD = 1			'--- 1 for alternating colors, like classic dot-matrix paper

INTYMUSIC_STAFF_COLOR	= FG_BLACK	'-- staff color. Colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
INTYMUSIC_TITLE_COLOR = FG_BLUE	'---Song title Color

INTYMUSIC_SONG_TITLE = 1			'--- 0 to disable vertical song title

'--- volume bar on each sound channel---
INTYMUSIC_VOLUMECARD = 43		'--- GRAM card,back of volume bar. 40 to 43. 40 is static/solid, 41 is checkerboard, 42=recommended, 43=bandaid.

'--- Music note color, by voice channel (drawn on top, scrolls down)----
iMusicNoteColor(0)=FG_DARKGREEN
iMusicNoteColor(1)=FG_RED
iMusicNoteColor(2)=FG_BLUE

'--- Piano key and Volume colors, by voice channel -- 2nd set flash effect. Use same colors on 2nd to disable hilite/blink
' SPR_BLACK,SPR_BLUE,SPR_RED,SPR_TAN,SPR_DARKGREEN,SPR_GREEN,SPR_YELLOW,SPR_WHITE,SPR_GREY,SPR_CYAN,SPR_ORANGE,SPR_BROWN,SPR_PINK,SPR_LIGHTBLUE,SPR_YELLOWGREEN,SPR_PURPLE			7
'--1st set--- for each voice channel---
#iMusicPianoColorA(0)=SPR_DARKGREEN
#iMusicPianoColorA(1)=SPR_RED
#iMusicPianoColorA(2)=SPR_BLUE
'--2nd set, flash---
#iMusicPianoColorB(0)=SPR_GREEN
#iMusicPianoColorB(1)=SPR_ORANGE
#iMusicPianoColorB(2)=SPR_LIGHTBLUE

'----Color stack----alternating background colors. STACK_BLACK,STACK_BLUE,STACK_RED,STACK_TAN,STACK_DARKGREEN,STACK_GREEN,STACK_YELLOW,STACK_WHITE
'STACK_GREY,STACK_CYAN,STACK_ORANGE,STACK_BROWN,STACK_PINK,STACK_LIGHTBLUE,STACK_YELLOWGREEN,STACK_PURPLE

BORDER BORDER_WHITE,0
MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
'MODE 0,STACK_GREY,STACK_LIGHTBLUE,STACK_WHITE,STACK_GREEN
'MODE 0,STACK_YELLOWGREEN,STACK_DARKGREEN,STACK_WHITE,STACK_GREEN
 
'========================== Options #1 End ===========================================================

'-----Required------ 
INCLUDE "IntyMusicPlayer.bas"		'Main music player

'========================== Options #2 - More customization ==============================================
'--Big data segment. If the assembler triggers an overflow error, use MUSIC JUMP to a different segment
ASM ORG $C040

'---------------- Song name, called from the title screen -------------------
IntyMusicInit_Credits: PROCEDURE
	'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
	'20 char max 1234567890123456789.  80+(half row)-(half of text length)
	PRINT COLOR FG_BLACK
	PRINT AT 80+10-3,"Music"
	PRINT COLOR FG_DARKGREEN
	PRINT AT 100+10-7,"demonstration"
	PRINT COLOR FG_GREEN
	PRINT AT 120+10-8,"TypeWriter Song"
END	

'=======================================Song to use======================================================

MyMusic:									'<-- Comment if it is defined in your .bas music file
INCLUDE "songs\Typewriter.bas"				'<-- song to use. Label must be named MyMusic.
DATA 60:MUSIC c2,s,s:MUSIC s,s,s:MUSIC STOP	'---In case the include file is missing

'If the song scrolls too fast or too slow, it can be asjusted, look at the INTYMUSIC_NEW_AUTO_SCROLL variable.
'For the demo song, "5" scrolls slower on some parts, faster on others.
'
'Too loud? Volume can be also adjusted, INTYMUSIC_PLAY_VOLUME. I also use it to adjust volume meter a bit.
'
'===============================
MyMusicName:
DATA " TypeWriter"		'12 characters max, no neeed to pad right

'===============================
DATA "            "		'Right padding, and, in case you forget a song name...

