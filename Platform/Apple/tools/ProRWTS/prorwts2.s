;license:BSD-3-Clause
;extended open/read/write binary file in ProDOS filesystem, with random access
;copyright (c) Peter Ferrie 2013-2021
;assemble using ACME

ver_02 = 1

!if ver_02 = 1 {
  !cpu 6502
} else { ;ver_02 = 0
  !cpu 65c02
} ;ver_02
*=$4000

;place no code before init label below.

                ;user-defined options
                verbose_info = 1        ;set to 1 to enable display of memory usage
                enable_floppy= 1        ;set to 1 to enable floppy drive support
                poll_drive   = 1        ;set to 1 to check if disk is in drive, recommended if allow_multi is enabled
                use_smartport= 1        ;set to 1 to enable support for more than two MicroDrive (or more than four CFFA) partitions
                override_adr = 1        ;set to 1 to require an explicit load address
                aligned_read = 0        ;set to 1 if all reads can be a multiple of block size (required for RWTS mode)
                enable_readseq=1        ;set to 1 to enable reading multiple sequential times from the same file without seek
                                        ;(exposes a fixed address that can be called for either floppy or hard disk support)
                enable_write = 1        ;set to 1 to enable write support
                                        ;file must exist already and its size cannot be altered
                                        ;writes occur in multiples of block size
                enable_format= 0        ;used only by RWTS mode, requires enable_write and fast_subindex
                enable_seek  = 1        ;set to 1 to enable seek support
                                        ;seeking with aligned_read=1 requires non-zero offset
                allow_multi  = 1        ;set to 1 to allow multiple floppies
                allow_zerovol= 0        ;set to 1 to support volume 0 (=last used volume)
                check_chksum = 1        ;set to 1 to enforce checksum verification for floppies
                allow_subdir = 0        ;set to 1 to allow opening subdirectories to access files
                might_exist  = 1        ;set to 1 if file is not known to always exist already
                                        ;makes use of status to indicate success or failure
                many_files   = 0        ;set to 1 to support more than 256 files in a directory
                detect_wp    = 0        ;detect write-protected floppy during writes
                allow_aux    = 1        ;set to 1 to allow read/write directly to/from aux memory
                                        ;requires load_high to be set for arbitrary memory access
                                        ;else driver must be running from same memory target
                                        ;i.e. running from main if accessing main, running from aux if accessing aux
                allow_saplings=1        ;enable support for saplings
                allow_trees  = 1        ;enable support for tree files, as opposed to only seedlings and saplings
                                        ;required in RWTS mode if file > 128kb
                fast_trees   = 1        ;keep tree block in memory, requires an additional 512 bytes of RAM
                always_trees = 0        ;set to 1 if the only file access involves tree files
                                        ;not compatible with allow_subdir, allow_saplings
                                        ;required in RWTS mode if allow_trees is enabled
                detect_treof = 0        ;detect EOF during read of tree files
                fast_subindex= 1        ;keep subindex block in memory, requires an additional 512 bytes of RAM
                                        ;halves the disk access for double the speed (ideal for RWTS mode)
                allow_sparse = 0        ;enable support for reading sparse files
                write_sparse = 0        ;enable support for writing to sparse files (blocks are allocated even if empty)
                                        ;used only by RWTS mode, writing to sparse files in non-RWTS mode will corrupt the file!
                bounds_check = 0        ;set to 1 to prevent access beyond the end of the file
                                        ;but limits file size to 64k-2 bytes.
                return_size  = 0        ;set to 1 to receive file size on open in read-only mode
                one_shot     = 0        ;set to 1 to load entire file in one pass (avoids the need to specify size)
                no_interrupts= 0        ;set to 1 to disable interrupts across calls
                detect_err   = 0        ;set to 1 to to detect errors in no_interrupts mode
                swap_zp      = 0        ;set to 1 to include code to preserve zpage
                                        ;used only by RWTS mode
                swap_scrn    = 1        ;set to 1 to preserve screen hole contents across SmartPort calls
                                        ;recommended if allow_aux is used, to avoid device reset
                                        ;requires 64 bytes to save all holes
                read_scrn    = 0        ;set to 1 to support reading into screen memory
                                        ;requires swap_scrn
                rwts_mode    = 0        ;set to 1 to enable emulation of DOS RWTS when running from hard disk
                                        ;uses a one-time open of a tree file, no other file access allowed
                                        ;use unique volume numbers to distinguish between images in the same file
                                        ;requires override_adr, allow_trees, always_trees
                                        ;not compatible with enable_floppy, allow_subdir, might_exist, bounds_check
                mem_swap     = 0        ;set to 1 if zpage can be swapped between main and aux, and swap_zp is unsuitable
                                        ;(caches index registers in code instead of zpage)
                load_high    = 0        ;set to 1 to load to top of RAM (either main or banked, enables a himem check)
                load_aux     = 1        ;load to aux memory, requires either swap_scrn or load_banked
                load_banked  = 1        ;set to 1 to load into banked RAM instead of main RAM (can be combined with load_aux for aux banked)
                lc_bank      = 1        ;load into specified bank (1 or 2) if load_banked=1
                one_page     = 0        ;set to 1 if verbose mode says that you should (smaller code)
                two_pages    = 1        ;default size
                three_pages  = 0        ;set to 1 if verbose mode says that you should (code is larger than two pages)

                ;user-defined driver load address
!if load_banked = 1 {
  !if load_high = 1 {
    !ifdef PASS2 {
    } else { ;PASS2 not defined
                reloc     = $fb00       ;page-aligned, as high as possible, the ideal value will be shown on mismatch
    } ;PASS2
  } else { ;load_high = 0
                reloc     = $d000       ;page-aligned, but otherwise wherever you want
  } ;load_high = 1
} else { ;load_banked = 0
  !if load_high = 1 {
    !ifdef PASS2 {
    } else { ;PASS2 not defined
                reloc     = $bf00       ;page-aligned, as high as possible, the ideal value will be shown on mismatch
    } ;PASS2
  } else { ;load_high = 0
                reloc     = $bc00       ;page-aligned, but otherwise wherever you want ($BC00 is common for rwts_mode)
  } ;load_high = 1
} ;load_banked = 1

                ;there are also buffers that can be moved if necessary:
                ;dirbuf, encbuf, treebuf (and corresponding hdd* versions that load to the same place)
                ;they are independent of each other so they can be placed separately
                ;see near EOF for those
                ;note that hddencbuf must be even-page-aligned in RWTS-mode

                ;zpage usage, arbitrary selection except for the "ProDOS constant" ones
                ;feel free to move them around

!if (might_exist + poll_drive) > 0 {
                status    = $3          ;returns non-zero on error
} ;might_exist = 1 or poll_drive = 1
!if write_sparse = 1 {
                sparseblk  = $3         ;(internal) last-read block was sparse if zero
} ;write_sparse = 1
!if allow_aux = 1 {
                auxreq    = $a          ;set to 1 to read/write aux memory, else main memory is used
} ;allow_aux = 1
                sizelo    = $6          ;set if enable_write=1 and writing, or reading, or if enable_seek=1 and seeking
                sizehi    = $7          ;set if enable_write=1 and writing, or reading, or if enable_seek=1 and seeking
!if (enable_write + enable_seek + allow_multi + rwts_mode) > 0 {
                reqcmd    = $2          ;set (read/write/seek) if enable_write=1 or enable_seek=1
                                        ;if allow_multi=1, bit 7 selects floppy drive in current slot (clear=drive 1, set=drive 2) during open call
                                        ;bit 7 must be clear for read/write/seek on opened file
} ;enable_write = 1 or enable_seek = 1 or allow_multi = 1 or rwts_mode = 1
                ldrlo     = $E          ;set to load address if override_adr=1
                ldrhi     = $F          ;set to load address if override_adr=1
                namlo     = $C          ;name of file to access
                namhi     = $D          ;name of file to access

!if enable_floppy = 1 {
                tmpsec    = $15         ;(internal) sector number read from disk
                reqsec    = $16         ;(internal) requested sector number
                curtrk    = $17         ;(internal) track number read from disk
} ;enable_floppy = 1

                command   = $42         ;ProDOS constant
                unit      = $43         ;ProDOS constant
                adrlo     = $44         ;ProDOS constant
                adrhi     = $45         ;ProDOS constant
                bloklo    = $46         ;ProDOS constant
                blokhi    = $47         ;ProDOS constant

                scratchlo = $48         ;(internal)
                scratchhi = $49         ;(internal)

                entries   = $18         ;(internal) total number of entries in directory
!if many_files = 1 {
                entrieshi = invalid    ;(internal) total number of entries in directory
} ;many_files = 1

!if mem_swap = 0 {
  !if rwts_mode = 1 {
                lasttree  = invalid    ;(internal) last used index in tree buffer
  } ;rwts_mode = 1
  !if allow_trees = 1 {
                treeidx   = $1b         ;(internal) index into tree block
                                        ;MH: must be just after blkoffhi for proper seek reset in LegendOS
    !if always_trees = 0 {
                istree    = $12         ;(internal) flag to indicate tree file
    } ;always_trees = 0
    !if fast_trees = 0 {
                treeblklo = invalid
                treeblkhi = invalid
    } ;fast_trees = 0
  } ;allow_trees = 1
                blkidx    = $1c         ;(internal) index into sapling block list
  !if rwts_mode = 1 {
                lastblk   = invalid     ;(internal) previous index into sapling block list
  } ;rwts_mode = 1
  !if ((bounds_check or return_size) > 0) and ((rwts_mode or one_shot) = 0) {
                bleftlo   = $13         ;(internal) bytes left in file
  } ;(bounds_check = 1 or return_size = 1) and (rwts_mode = 0 and one_shot = 0)
  !if ((bounds_check or return_size or aligned_read) > 0) and ((rwts_mode or one_shot) = 0) {
                blefthi   = $14         ;(internal) bytes left in file
  } ;(bounds_check = 1 or return_size = 1 or aligned_read = 1) and (rwts_mode and one_shot = 0)
  !if aligned_read = 0 {
                blkofflo  = $19         ;(internal) offset within cache block
                blkoffhi  = $1a         ;(internal) offset within cache block
  } ;aligned_read = 0
} ;mem_swap = 0

!if enable_floppy = 1 {
                step      = $1d         ;(internal) state for stepper motor
                tmptrk    = $1e         ;(internal) temporary copy of current track
                phase     = $1f         ;(internal) current phase for seek
} ;enable_floppy = 1

                ;constants
                cmdseek   = 0           ;requires enable_seek=1
                cmdread   = 1           ;requires enable_write=1
                cmdwrite  = 2           ;requires enable_write=1
                SETKBD    = $fe89
                SETVID    = $fe93
                DEVNUM    = $bf30
                PHASEOFF  = $c080
                PHASEON   = $c081
                MOTOROFF  = $c088
                MOTORON   = $c089
                DRV0EN    = $c08a
                Q6L       = $c08c
                Q6H       = $c08d
                Q7L       = $c08e
                Q7H       = $c08f
                MLI       = $bf00
                NAME_LENGTH = $4        ;ProDOS constant
                MASK_SUBDIR = $d0       ;ProDOS constant
                MASK_ALL    = $f0       ;ProDOS constant
                KEY_POINTER = $11       ;ProDOS constant
                EOF_LO    = $15         ;ProDOS constant
                EOF_HI    = $16         ;ProDOS constant
                AUX_TYPE  = $1f         ;ProDOS constant
                ENTRY_SIZE = $27        ;ProDOS constant
                NEXT_BLOCK_LO = $2      ;ProDOS constant
                NEXT_BLOCK_HI = $3      ;ProDOS constant
                SAPLING   = $20         ;ProDOS constant
                FILE_COUNT = $25        ;ProDOS constant
                DEVADR01HI = $bf11      ;ProDOS constant
                ROMIN     = $c081
                LCBANK2   = $c08b
                CLRAUXRD  = $c002
                CLRAUXWR  = $c004
                SETAUXWR  = $c005
                CLRAUXZP  = $c008
                SETAUXZP  = $c009

                D1S1      = 1           ;disk 1 side 1 volume ID if rwts_mode enabled

init            jsr     SETKBD
                jsr     SETVID
                lda     DEVNUM
                sta     x80_parms + 1
                sta     unrunit1 + 1
                and     #$70
!if (enable_floppy + enable_write) > 1 {
                sta     unrslot1 + 1
                sta     unrslot2 + 1
                sta     unrslot3 + 1
                sta     unrslot4 + 1
} ;enable_floppy = 1 and enable_write = 1
                pha
!if enable_floppy = 1 {
                ora     #<PHASEOFF
                sta     unrseek + 1
                ora     #<MOTOROFF
                sta     unrdrvoff1 + 1
  !if no_interrupts = 1 {
                sta     unrdrvoff2 + 1
  } else { ;no_interrupts = 0
                sta     unrdrvoff4 + 1
    !if one_shot = 1 {
                sta     unrdrvoff5 + 1
    } ;one_shot = 1
  } ;no_interrupts = 1
  !if (might_exist + poll_drive) > 0 {
                sta     unrdrvoff3 + 1
  } ;might_exist = 1 or poll_drive = 1
                tax
                inx ;MOTORON
                stx     unrdrvon1 + 1
                stx     unrdrvon2 + 1
                inx ;DRV0EN
  !if allow_multi = 1 {
                stx     unrdrvsel2 + 1
  } ;allow_multi = 1
                inx
  !if allow_multi = 1 {
                stx     unrdrvsel1 + 1
  } ;allow_multi = 1
                inx ;Q6L
                stx     unrread1 + 1
                stx     unrread2 + 1
                stx     unrread3 + 1
                stx     unrread4 + 1
                stx     unrread5 + 1
  !if check_chksum = 1 {
                stx     unrread6 + 1
  } ;check_chksum = 1
} ;enable_floppy = 1
                ldx     #1
                stx     namlo
                inx
                stx     namhi

                ;fetch path, if any

                jsr     MLI
                !byte   $c7
                !word   c7_parms
                ldx     $200
                dex
                stx     sizelo
                sec
                bmi     +++

                ;find current directory name in directory

                php

readblock       jsr     MLI
                !byte   $80
                !word   x80_parms

                lda     #<(readbuff + NAME_LENGTH)
                sta     scratchlo
                lda     #>(readbuff + NAME_LENGTH)
                sta     scratchhi
inextent        ldy     #0
                lda     (scratchlo), y
                pha
                and     #$0f
                tax
--              iny
                lda     (scratchlo), y
                cmp     (namlo), y
                beq     ifoundname

                ;match failed, move to next directory in this block, if possible

-               pla

skiphdr         clc
                lda     scratchlo
                adc     #ENTRY_SIZE
                sta     scratchlo
                bcc     +

                ;there can be only one page crossed, so we can increment instead of adc

                inc     scratchhi
+               cmp     #<(readbuff + $1ff) ;4 + ($27 * $0d)
                lda     scratchhi
                sbc     #>(readbuff + $1ff)
                bcc     inextent

                ;read next directory block when we reach the end of this block

                lda     readbuff + NEXT_BLOCK_LO
                ldx     readbuff + NEXT_BLOCK_HI
                bcs     +

ifoundname      dex
                bne     --

                ;parse path until last directory is seen

                iny
                lda     (namlo), y
                cmp     #'/'
                bne     -
                pla
                and     #$20 ;Volume Directory Header XOR subdirectory
                beq     adjpath
                pla
                clc
                php
                lsr
                bcc     skiphdr
                inx

adjpath         tya
                eor     #$ff
                adc     sizelo
                sta     sizelo
                clc
                tya
                adc     namlo
                sta     namlo
                dex
                beq     ++

                ;cache block number of current directory
                ;as starting position for subsequent searches

                ldy     #(KEY_POINTER + 1)
                lda     (scratchlo), y
                tax
                dey
                lda     (scratchlo), y
!if enable_floppy = 1 {
                sta     unrblocklo + 1
                stx     unrblockhi + 1
} ;enable_floppy = 1
                sta     unrhddblocklo + 1
                stx     unrhddblockhi + 1
+               sta     x80_parms + 4
                stx     x80_parms + 5
++              lda     sizelo
                bne     readblock
                pla

                ;unit to slot for ProDOS interface

+++             pla
                lsr
                lsr
                lsr
                tay
                ldx     DEVADR01HI, y
                cpx     #$c1
                bcc     +
                cpx     #$c8
                bcc     set_slot
+
!if enable_floppy = 1 {

                ;check if current device is floppy

                lsr
                ora     #$c0
                tax
                stx     scratchhi
                ldy     #0
                sty     scratchlo
                iny
                lda     (scratchlo), y
                cmp     #$20
                bne     not_floppy
                iny
                iny
                lda     (scratchlo), y
                bne     not_floppy
                iny
                iny
                lda     (scratchlo), y
                cmp     #3
                bne     not_floppy
                ldy     #$ff
                lda     (scratchlo), y
                beq     set_slot

not_floppy      inx
} ;enable_floppy = 1

                ;find SmartPort device for basic MicroDrive support

-               dex
                stx     scratchhi
                ldy     #0
                sty     scratchlo
                iny
                lda     (scratchlo), y
                cmp     #$20
                bne     -
                iny
                iny
                lda     (scratchlo), y
                bne     -
                iny
                iny
                lda     (scratchlo), y
                cmp     #3
                bne     -
                ldy     #$ff
                lda     (scratchlo), y
                beq     -

set_slot        stx     slot + 2
                stx     unrentry + 2
slot            ldx     $cfff
                stx     unrentry + 1
!if enable_floppy = 1 {
                php
} ;enable_floppy = 1
!if use_smartport = 1 {
  !if enable_floppy = 1 {
                beq     +
                bcs     ++
+               jmp     bankram
++
  } else { ;enable_floppy = 0
    !if rwts_mode = 0 {
                bcc     bankram
    } else { ;rwts_mode = 1
                bcs     +
                jmp     bankram
+
    } ;rwts_mode = 0
  } ;enable_floppy = 1

                ldy     #$8c ;STY
  !if (rwts_mode + enable_write) > 1 {
                sty     unrcommand1
  } ;rwts_mode = 1 and enable_write = 1
                sty     unrcommand3
                lda     #<pcommand
  !if (rwts_mode + enable_write) > 1 {
                sta     unrcommand1 + 1
  } ;rwts_mode = 1 and enable_write = 1
  !if (rwts_mode + aligned_read + (enable_write xor 1)) = 0 {
                sta     unrcommand2 + 1
  } ;rwts_mode = 0 and aligned_read = 0 and enable_write = 1
                sta     unrcommand3 + 1
                lda     #>pcommand
  !if (rwts_mode + enable_write) > 1 {
                sta     unrcommand1 + 2
  } ;rwts_mode = 1 and enable_write = 1
  !if (rwts_mode + aligned_read + (enable_write xor 1)) = 0 {
                sta     unrcommand2 + 2
  } ;rwts_mode = 0 and aligned_read = 0 and enable_write = 1
                sta     unrcommand3 + 2
                iny      ;STA
                sty     unrblokhi1
                sty     unrunit1 + 2
                iny     ;STX
  !if (rwts_mode + aligned_read + (enable_write xor 1)) = 0 {
                sty     unrcommand2
  } ;rwts_mode = 0 and aligned_read = 0 and enable_write = 1
                sty     unrbloklo1
                lda     #>pblock
                pblock_enabled=1
                sta     unrbloklo1 + 2
  !if (rwts_mode + write_sparse) > 1 {
                sta     unrbloklo2 + 2
  } ;rwts_mode = 1 and write_sparse = 1
                ;;lda     #>(pblock + 1)
                ;;pblock1_enabled=1
                sta     unrblokhi1 + 2
  !if (rwts_mode + write_sparse) > 1 {
                sta     unrblokhi2 + 2
                sta     unrblokhi3 + 2
  } ;rwts_mode = 1 and write_sparse = 1
                lda     #>paddr
                sta     unrunit1 + 4
                ldy     #<pblock
                sty     unrbloklo1 + 1
  !if (rwts_mode + write_sparse) > 1 {
                sty     unrbloklo2 + 1
  } ;rwts_mode = 1 and write_sparse = 1
                iny
                sty     unrblokhi1 + 1
  !if (rwts_mode + write_sparse) > 1 {
                sty     unrblokhi2 + 1
                sty     unrblokhi3 + 1
  } ;rwts_mode = 1 and write_sparse = 1
                lda     #$a5 ;LDA
                sta     unrunit1
  !if (rwts_mode + write_sparse) > 1 {
                lda     #$ee ;INC
                sta     unrblokhi2
                ldy     #$ad ;LDA
                sty     unrblokhi3
                iny ;LDX
                sty     unrbloklo2
  } ;rwts_mode = 1 and write_sparse = 1
                lda     #adrlo
                sta     unrunit1 + 1
                lda     #<paddr
                sta     unrunit1 + 3

                ;use SmartPort entrypoint instead

                inx
                inx
                inx
                stx     unrentry + 1

                ldx     #2
                stx     x80_parms + 4
                lda     #0
                sta     x80_parms + 5
                jsr     MLI
                !byte   $80
                !word   x80_parms
                lda     #cmdread
                sta     unrpcommand
                lda     #$ea
                sta     hackstar

iterunit        inc     unrunit2
                jsr     unrentrysei

+               ldy     #$10
-               lda     readbuff + 3, y
                cmp     readbuff + $203, y
                bne     iterunit
                dey
                bne     -
                lda     #$68
                sta     hackstar
                lda     #<packet
                sta     unrppacket
                lda     #>packet
                sta     unrppacket + 1
} ;use_smartport = 1

bankram
!if load_banked = 1 {
                lda     LCBANK2 - ((lc_bank - 1) * 8)
                lda     LCBANK2 - ((lc_bank - 1) * 8)
} ;load_banked = 1
!if enable_floppy = 1 {
                ldx     #>unrelocdsk
                ldy     #<unrelocdsk
                plp
                php
                beq     copydrv
                ldx     #>unrelochdd
                ldy     #<unrelochdd

copydrv         stx     scratchhi
                sty     scratchlo
                ldx     #>((codeend - rdwrpart) + $ff)
                ldy     #0
  !if (load_aux and (load_banked xor 1)) = 1 {
                sta     SETAUXWR
  } ;load_aux = 1 and load_banked = 0
-               lda     (scratchlo), y
  !if (load_aux + load_banked) > 1 {
                sta     SETAUXZP
  } ;load_aux = 1 and load_banked = 1
reladr          sta     reloc, y
  !if (load_aux + load_banked) > 1 {
                sta     CLRAUXZP
  } ;load_aux = 1 and load_banked = 1
                iny
                bne     -
                inc     scratchhi
  !if (load_aux and (load_banked xor 1)) = 1 {
                sta     CLRAUXWR
  } ;load_aux = 1 and load_banked = 0
                inc     reladr + 2
  !if (load_aux and (load_banked xor 1)) = 1 {
                sta     SETAUXWR
  } ;load_aux = 1 and load_banked = 0
                dex
                bne     -
                plp
  !if (load_aux + load_banked) > 1 {
                sta     SETAUXZP
  } ;load_aux = 1 and load_banked = 1
  !if swap_scrn = 1 {
                beq     +
                jsr     saveslot
                lda     #$91
                sta     initpatch
  } ;swap_scrn = 1
                bne     ++
+

                ;build 6-and-2 denibbilisation table

                ldx     #$16
--              stx     scratchlo
                txa
                asl
                bit     scratchlo
                beq     +
                ora     scratchlo
                eor     #$ff
                and     #$7e
-               bcs     +
                lsr
                bne     -
                tya
                sta     nibtbl - $16, x
  !if enable_write = 1 {
                ;and 6-and-2 nibbilisation table if writing

                txa
                ora     #$80
                sta     xlattbl, y
  } ;enable_write = 1
                iny
+               inx
                bpl     --

unrdrvon1       lda     MOTORON
                jsr     readadr
                lda     curtrk
                sta     trackd1

  !if allow_multi = 1 {
unrdrvsel1      lda     DRV0EN + 1
                jsr     spinup
                jsr     poll
                beq     +
                lda     #$c8 ;iny
                sta     twodrives
                lda     #0
                sta     phase
                ldx     #$22
                jsr     seek
+               inc     driveind + 1
  } ;allow_multi = 1
unrdrvoff1      lda     MOTOROFF
++
} else { ;enable_floppy = 0
  !ifdef PASS2 {
    !if >(hddcodeend - reloc) > 0 {
      !if one_page = 1 {
        !error "one_page must be 0"
      } ;one_page = 0
      !if >(hddcodeend - reloc) > 1 {
        !if three_pages = 0 {
          !error "three_pages must be 1"
        } ;three_pages = 0
      } ;hddcodeend
    } ;hddcodeend
  } ;PASS2
  !if three_pages = 1 {
                ldx     #>(hddcodeend + $ff - reloc)
  } ;three_pages = 1
                ldy     #0
  !if load_aux = 1 {
                sta     SETAUXWR + (load_banked * 4) ;SETAUXWR or SETAUXZP
  } ;load_aux = 1
multicopy
-               lda     unrelochdd, y
                sta     reloc, y

  !if three_pages = 0 {
    !if two_pages = 1 {
                lda     unrelochdd + $100, y
                sta     reloc + $100, y
    } ;two_pages = 1
  } ;three_pages = 0
                iny
                bne     -
  !if three_pages = 1 {
    !if (load_aux and (load_banked xor 1)) = 1 {
                sta     CLRAUXWR
    } ;load_aux = 1 and load_banked = 0
                inc     multicopy + 2
                inc     multicopy + 5
    !if (load_aux and (load_banked xor 1)) = 1 {
                sta     SETAUXWR
    } ;load_aux = 1 and load_banked = 0
                dex
                bne     multicopy
  } ;three_pages = 1

  !if swap_scrn = 1 {
                jsr     saveslot
                lda     #$91
                sta     initpatch
  } ;swap_scrn = 1
} ;enable_floppy = 1

!if rwts_mode = 1 {
                ;read volume directory key block
                ;self-modified by init code

hddopendir
unrhddblocklo = *
                ldx     #2
unrhddblockhi = *
                lda     #0
hddreaddir1     jsr     hddreaddirsel

hddfirstent     lda     #NAME_LENGTH
                sta     scratchlo
                lda     #>(hdddirbuf - 1)
                sta     scratchhi

                ;there can be only one page crossed, so we can increment here

hddnextent1     inc     scratchhi
hddnextent      ldy     #0

                ;match name lengths before attempting to match names

                lda     (scratchlo), y
                and     #$0f
                tax
                inx
-               cmp     filename, y
                beq     hddfoundname

                ;match failed, move to next entry in this block, if possible

+               clc
                lda     scratchlo
                adc     #ENTRY_SIZE
                sta     scratchlo
                bcs     hddnextent1
                cmp     #$ff ;4 + ($27 * $0d)
                bne     hddnextent

                ;read next directory block when we reach the end of this block

                ldx     hdddirbuf + NEXT_BLOCK_LO
                lda     hdddirbuf + NEXT_BLOCK_HI
                bcs     hddreaddir1

hddfoundname    iny
                lda     (scratchlo), y
                dex
                bne -

  !if ((swap_zp xor 1) + mem_swap) > 0 {
    !if allow_trees = 1 {
                stx     treeidx
                sty     lasttree ;guarantee no match
    } ;allow_trees = 1
                stx     blkidx
                sty     lastblk ;guarantee no match
  } else { ;swap_zp = 1 and mem_swap = 0
    !if allow_trees = 1 {
                stx     zp_array + treeidx - first_zp
                sty     zp_array + lasttree - first_zp ;guarantee no match
    } ;allow_trees = 0
                stx     zp_array + blkidx - first_zp
                sty     zp_array + lastblk - first_zp ;guarantee no match
  } ;swap_zp = 0 or mem_swap = 1

  !if allow_trees = 1 {
                ;fetch KEY_POINTER

                ldy     #KEY_POINTER
                lda     (scratchlo), y
    !if fast_trees = 0 {
      !if ((swap_zp xor 1) + mem_swap) > 0 {
                sta     treeblklo
      } else { ;swap_zp = 1 and mem_swap = 0
                sta     zp_array + treeblklo - first_zp
      } ;swap_zp = 0 or mem_swap = 1
    } else { ;fast_trees = 1
                tax
    } ;fast_trees = 0
                iny
                lda     (scratchlo), y
    !if fast_trees = 0 {
      !if ((swap_zp xor 1) + mem_swap) > 0 {
                sta     treeblkhi
      } else { ;swap_zp = 1 and mem_swap = 0
                sta     zp_array + treeblkhi - first_zp
      } ;swap_zp = 0 or mem_swap = 1
    } else { ;fast_trees = 1
                ldy     #>hddtreebuf
                jsr     hddreaddirsect
    } ;fast_trees = 0
  } ;allow_trees = 1

                lda     #>iob
                ldy     #<iob
                jsr     reloc
                inc     sect
                inc     addr + 1
                lda     #>iob
                ldy     #<iob
                jsr     reloc
                lda     #9
                sta     sect
                lda     #$bf
                sta     addr + 1
                lda     #>iob
                ldy     #<iob
                jsr     reloc
                ldx     #$60
                jmp     $b700

filename        !byte   filename_e-filename_b
filename_b      !text   "DISKIMAGE"
filename_e
iob             !byte   0, 0, 0, 0
trak            !byte   0
sect            !byte   0
                !byte   0, 0
addr            !byte   0, $b6
                !byte   0, 0, 1, 0, 0
} else { ;rwts_mode = 0
  !if load_aux = 1 {
                sta     CLRAUXWR + (load_banked * 4) ;CLRAUXWR or CLRAUXZP
  } ;load_aux = 1
  !if load_banked = 1 {
                lda     ROMIN
  } ;load_banked = 1
                rts
} ;rwts_mode = 1

c7_parms        !byte   1
                !word   $200

x80_parms       !byte   3, $d1
                !word   readbuff, 2

!if enable_floppy = 1 {
unrelocdsk
!pseudopc reloc {
rdwrpart
  !if (enable_readseq + allow_subdir) > 0 {
                jmp     rdwrfile
  } ;enable_readseq = 1 or allow_subdir = 1
opendir
  !if no_interrupts = 1 {
    !if detect_err = 1 {
                clc
    } ;detect_err = 1
                php
                sei
                jsr     +
    !if detect_err = 1 {
                pla
                adc     #0
                pha
    } ;detect_err = 1
                plp
unrdrvoff2 = unrelocdsk + (* - reloc)
                lda     MOTOROFF
                rts
+
  } ;no_interrupts = 1

                jsr     prepdrive

                ;read volume directory key block
                ;self-modified by init code

unrblocklo = unrelocdsk + (* - reloc)
                ldx     #2
unrblockhi = unrelocdsk + (* - reloc)
                lda     #0
                jsr     readdirsel

readdir
  !if allow_subdir = 1 {
                jsr     prepdrive
  } ;allow_subdir = 1
  !if might_exist = 1 {
                lda     dirbuf + FILE_COUNT ;assuming only 256 files per subdirectory
                sta     entries
    !if many_files = 1 {
                lda     dirbuf + FILE_COUNT + 1
                sta     entrieshi
    } ;many_files = 1
  } ;might_exist = 1

                lda     #NAME_LENGTH + ENTRY_SIZE
firstent        sta     scratchlo
                lda     #>(dirbuf - 1)
                sta     scratchhi

                ;there can be only one page crossed, so we can increment here

nextent1        inc     scratchhi
nextent         ldy     #0
  !if (might_exist + allow_subdir + allow_saplings + (allow_trees xor always_trees)) > 0 {
                lda     (scratchlo), y
    !if might_exist = 1 {
                sty     status

                ;skip deleted entries without counting

                and     #MASK_ALL
                beq     +
    } ;might_exist = 1

    !if (allow_subdir + allow_saplings + (allow_trees xor always_trees)) > 0 {
                ;remember type
                ;now bits 5-4 are represented by carry (subdirectory), sign (sapling)

                asl
                asl

      !if allow_trees = 1 {
                ;now bits 5-3 are represented by carry (subdirectory), sign (sapling),
                ;overflow (seedling), and sign+overflow (tree)

                sta     treeidx
                bit     treeidx
      } ;allow_trees = 1
                php
    } ;allow_subdir = 1 or allow_saplings = 1 or (allow_trees = 1 and always_trees = 0)
  } ;might_exist = 1 or allow_subdir = 1 or allow_saplings = 1 or (allows_trees = 1 and always_trees = 0)

                ;match name lengths before attempting to match names

                lda     (scratchlo), y
                and     #$0f
                tax
                inx
-               cmp     (namlo), y
                beq     foundname

                ;match failed, check if any directory entries remain

  !if (allow_subdir + allow_saplings + (allow_trees xor always_trees)) > 0 {
                plp
  } ;allow_subdir = 1 or allow_saplings = 1 or (allow_trees = 1 and always_trees = 0)
  !if might_exist = 1 {
                dec     entries
                bne     +
    !if many_files = 1 {
                lda     entrieshi
                bne     ++
    } ;many_files = 1
  } ;might_exist = 1
  !if (might_exist + poll_drive) > 0 {
nodisk          inc     status
    !if no_interrupts = 0 {
unrdrvoff3 = unrelocdsk + (* - reloc)
                lda     MOTOROFF
    } ;no_interrupts = 0
                rts
  } ;might_exist = 1 or poll_drive = 1

  !if (might_exist + many_files) > 1 {
++              dec     entrieshi
  } ;might_exist = 1 and many_files = 1

                ;move to next entry in this block, if possible

+               clc
                lda     scratchlo
                adc     #ENTRY_SIZE
                sta     scratchlo
                bcs     nextent1
                cmp     #$ff ;4 + ($27 * $0d)
                bne     nextent

                ;read next directory block when we reach the end of this block

                ldx     dirbuf + NEXT_BLOCK_LO
                lda     dirbuf + NEXT_BLOCK_HI
                jsr     readdirsec
                lda     #NAME_LENGTH
                bne     firstent

foundname       iny
                lda     (scratchlo), y
                dex
                bne     -

                ;initialise essential variables

  !if allow_trees = 1 {
                stx     treeidx
    !if always_trees = 0 {
                stx     istree
    } ;always_trees = 0
  } ;allow_trees = 1
                stx     blkidx
  !if (aligned_read + one_shot) = 0 {
                stx     blkofflo
                stx     blkoffhi
  } ;aligned_read = 0 and one_shot = 0
  !if enable_write = 1 {
    !if aligned_read = 0 {
                ldy     reqcmd
                cpy     #cmdwrite ;control carry instead of zero
      !if one_shot = 0 {
                bne     +
      } ;one_shot = 0
    } ;aligned_read = 0
    !if one_shot = 0 {

                ;round requested size up to nearest block if writing

                lda     sizelo
                adc     #$fe
                lda     sizehi
                adc     #1
                and     #$fe
                sta     sizehi
      !if aligned_read = 0 {
                stx     sizelo
        !if bounds_check = 1 {
                sec
        } ;bounds_check = 1
      } ;aligned_read = 0
    } ;one_shot = 0
+
  } ;enable_write = 1

  !if (bounds_check + return_size + one_shot) > 0 {
                ;cache EOF (file size, loaded backwards)

                ldy     #EOF_HI
                lda     (scratchlo), y
    !if (enable_write + aligned_read) > 0 {
                tax
                dey ;EOF_LO
                lda     (scratchlo), y

                ;round file size up to nearest block if writing without aligned reads
                ;or always if using aligned reads

      !if aligned_read = 0 {
                bcc     +
      } else { ;aligned_read = 1
        !if enable_write = 1 {
                sec
        } ;enable_write = 1
      } ;aligned_read = 0
                adc     #$fe
                txa
                adc     #1
                and     #$fe
      !if aligned_read = 0 {
                tax
                lda     #0
        !if one_shot = 0 {
+               stx     blefthi
                sta     bleftlo
        } else { ;one_shot = 1
+               stx     sizehi
                sta     sizelo
        } ;one_shot = 0
      } else { ;aligned_read = 1
        !if one_shot = 0 {
                sta     blefthi
        } else { ;one_shot = 1
                sta     sizehi
        } ;one_shot = 0
      } ;aligned_read = 0
    } else { ;enable_write = 0 and aligned_read = 0
      !if one_shot = 0 {
                sta     blefthi
      } else { ;one_shot = 1
                sta     sizehi
      } ;one_shot = 0
                dey ;EOF_LO
                lda     (scratchlo), y
      !if one_shot = 0 {
                sta     bleftlo
      } else { ;one_shot = 1
                sta     sizelo
      } ;one_shot = 0
    } ;enable_write = 1 or aligned_read = 1
  } ;bounds_check = 1 or return_size = 1 or one_shot = 1
                ;cache AUX_TYPE (load offset for binary files)

  !if override_adr = 0 {
                ldy     #AUX_TYPE
                lda     (scratchlo), y
    !if (allow_subdir + allow_saplings + allow_trees + (aligned_read xor 1)) > 0 {
                sta     ldrlo
                iny
                lda     (scratchlo), y
                sta     ldrhi
    } else { ;allow_subdir = 0 and allow_saplings = 0 and allow_trees = 0 and aligned_read = 1
                pha
                iny
                lda     (scratchlo), y
                pha
    } ;allow_subdir = 1 or allow_saplings = 1 or allow_trees = 1 or aligned_read = 0
  } ;override_adr = 0

                ;cache KEY_POINTER

                ldy     #KEY_POINTER
                lda     (scratchlo), y
                tax
  !if (allow_subdir + allow_saplings + allow_trees) > 0 {
                sta     dirbuf
    !if (allow_trees + (fast_trees xor 1)) > 1 {
                sta     treeblklo
    } ;allow_trees = 1 and fast_trees = 0
                iny
                lda     (scratchlo), y
                sta     dirbuf + 256
    !if (allow_trees + (fast_trees xor 1)) > 1 {
                sta     treeblkhi
    } ;allow_trees = 1 and fast_trees = 0

    !if (allow_saplings + write_sparse) > 1 {
                ;clear dirbuf in case sparse sapling becomes seedling

                pha
                ldy     #1
                lda     #0
-               sta     dirbuf, y
                sta     dirbuf + 256, y
                iny
                bne     -
                pla
    } ;allow_saplings = 1 and write_sparse = 1

    !if always_trees = 0 {
                plp
                bpl     ++
      !if allow_subdir = 1 {
                php
      } ;allow_subdir = 1
      !if allow_trees = 1 {
                ldy     #>dirbuf
                bvc     +
        !if fast_trees = 1 {
                ldy     #>treebuf
        } ;fast_trees = 1
                sty     istree
+
      } ;allow_trees = 1
    } else { ;always_trees = 1
                ldy     #>treebuf
    } ;always_trees = 0
  } else { ;allow_subdir = 0 and allow_saplings = 0 and allow_trees = 0
                iny
                lda     (scratchlo), y
  } ;allow_subdir = 1 or allow_saplings = 1 or allow_trees = 1

                ;read index block in case of sapling or tree

                jsr     readdirsect

  !if allow_subdir = 1 {
                plp
  } ;allow_subdir = 1
++
                ;skip some stuff
                ;drive is on already
                ;and interrupt control is in place

                jmp     rdwrfilei

rdwrfile
  !if allow_subdir = 1 {
                jsr     prepdrive
                clc
  } ;allow_subdir = 1
  !if no_interrupts = 1 {
    !if detect_err = 1 {
      !if allow_subdir = 0 {
                clc
      } ;allow_subdir = 0
    } ;detect_err = 1
                php
                sei
                jsr     +
    !if detect_err = 1 {
                pla
                adc     #0
                pha
    } ;detect_err = 1
                plp
unrdrvoff3 = unrelocdsk + (* - reloc)
                lda     MOTOROFF
                rts
+
  } ;no_interrupts = 1

  !if allow_multi = 1 {
                ldy     driveind + 1
  } ;allow_multi = 1
                jsr     prepdrivei

rdwrfilei
  !if (override_adr + allow_subdir + allow_saplings + allow_trees + (aligned_read xor 1)) > 0 {
                ;restore load offset

                ldx     ldrhi
                lda     ldrlo
    !if allow_subdir = 1 {
                ;check file type and fake size and load address for subdirectories

                bcc     +
                ldy     #2
                sty     sizehi
                ldx     #>dirbuf
                lda     #0
      !if aligned_read = 0 {
                sta     sizelo
      } ;aligned_read = 0
+
    } ;allow_subdir = 1
                sta     adrlo
                stx     adrhi
  } else { ;override_adr = 0 and allow_subdir = 0 and allow_saplings = 0 and allow_trees = 0 and aligned_read = 1
                pla
                sta     adrhi
                pla
                sta     adrlo
  } ;override_adr = 1 or allow_subdir = 1 or allow_saplings = 1 or allow_trees = 1 or aligned_read = 0

                ;set requested size to min(length, requested size)

  !if aligned_read = 0 {
    !if bounds_check = 1 {
                ldy     bleftlo
                cpy     sizelo
                lda     blefthi
                tax
                sbc     sizehi
                bcs     copyblock
                sty     sizelo
                stx     sizehi
    } ;bounds_check = 1

copyblock
    !if allow_aux = 1 {
                ldx     auxreq
                jsr     setaux
    } ;allow_aux = 1
    !if one_shot = 0 {
      !if enable_write = 1 {
                lda     reqcmd
                lsr
                bne     rdwrloop
      } ;enable_write = 1

                ;if offset is non-zero then we return from cache

                lda     blkofflo
                tax
                ora     blkoffhi
                beq     rdwrloop
                lda     sizehi
                pha
                lda     sizelo
                pha
                lda     adrhi
                sta     scratchhi
                lda     adrlo
                sta     scratchlo
                stx     adrlo
                lda     #>encbuf
                clc
                adc     blkoffhi
                sta     adrhi

                ;determine bytes left in block

                lda     #1
                sbc     blkofflo
                tay
                lda     #2
                sbc     blkoffhi
                tax

                ;set requested size to min(bytes left, requested size)

                cpy     sizelo
                sbc     sizehi
                bcs     +
                sty     sizelo
                stx     sizehi
+
      !if enable_seek = 1 {
                lda     sizehi
      } else { ;enable_seek = 0
                ldy     sizehi
      } ;enable_seek = 1
                jsr     copycache

                ;align to next block and resume read

                lda     ldrlo
                adc     sizelo
                sta     ldrlo
                lda     ldrhi
                adc     sizehi
                sta     ldrhi
                sec
                pla
                sbc     sizelo
                sta     sizelo
                pla
                sbc     sizehi
                sta     sizehi
                ora     sizelo
      !if allow_subdir = 1 {
        !if no_interrupts = 1 {
                clc
                bne     rdwrfilei
        } else { ;no_interrupts = 0
                bne     rdwrfile
        } ;no_interrupts = 1
      } else { ;allow_subdir = 0
                bne     rdwrfilei
      } ;allow_subdir = 1
      !if allow_aux = 0 {
                rts
      } else { ;allow_aux = 1
                beq     rdwrdone
      } ;allow_aux = 0
    } ;one_shot = 0
  } else { ;aligned_read = 1
    !if bounds_check = 1 {
                lda     blefthi
                cmp     sizehi
                bcs     +
                sta     sizehi
+
    } ;bounds_check = 1
    !if allow_aux = 1 {
                ldx     auxreq
                jsr     setaux
    } ;allow_aux = 1
  } ;aligned_read = 0

rdwrloop
  !if aligned_read = 0 {
    !if (enable_write + enable_seek) > 0 {
                ldx     reqcmd
    } ;enable_write = 1 or enable_seek = 1

                ;set read/write size to min(length, $200)

                lda     sizehi
                cmp     #2
                bcs     +
                pha

                ;redirect read to private buffer for partial copy

                lda     adrhi
                pha
                lda     adrlo
                pha
                lda     #>encbuf
                sta     adrhi
    !if ver_02 = 1 {
                ldx     #0
                stx     adrlo
      !if (enable_write + enable_seek) > 0 {
                inx ;ldx #cmdread
      } ;enable_write = 1 or enable_seek = 1
    } else { ;ver_02 = 0
                stz     adrlo
      !if (enable_write + enable_seek) > 0 {
                ldx     #cmdread
      } ;enable_write = 1 or enable_seek = 1
    } ;ver_02 = 1
+
  } ;aligned_read = 0

  !if allow_trees = 1 {
                ;read tree data block only if tree and not read already
                ;the indication of having read already is that at least one sapling/seed block entry has been read, too

                ldy     blkidx
                bne     +
    !if always_trees = 0 {
                lda     istree
                beq     +
    } ;always_trees = 0
                lda     adrhi
                pha
                lda     adrlo
                pha
    !if ((aligned_read xor 1) + (enable_write or enable_seek)) > 1 {
      !if ver_02 = 1 {
                txa
                pha
      } else { ;ver_02 = 0
                phx
      } ;ver_02 = 1
    } ;aligned_read = 0 and (enable_write = 1 or enable_seek = 1)
    !if aligned_read = 0 {
                php
    } ;aligned_read = 0
                lda     #>dirbuf
                sta     adrhi
                sty     adrlo

                ;fetch tree data block and read it

    !if fast_trees = 0 {
                ldx     treeblklo
                lda     treeblkhi
                jsr     readdirsel
    } ;fast_trees = 0
                ldy     treeidx
                inc     treeidx
                ldx     treebuf, y
                lda     treebuf + 256, y
    !if detect_treof = 1 {
                bne     noteof1
                tay
                txa
                bne     fixy1
      !if aligned_read = 0 {
                plp
                bcs     fewpop
                pla
                pla
                pla
fewpop
      } ;aligned_read = 0
                pla
                pla
                sec
                rts
fixy1           tya
noteof1
    } ;detect_treof = 1

    !if fast_trees = 0 {
                jsr     seekrd
    } else { ;fast_trees = 1
                jsr     readdirsel
    } ;fast_trees = 0

    !if aligned_read = 0 {
                plp
    } ;aligned_read = 0
    !if ((aligned_read xor 1) + (enable_write or enable_seek)) > 1 {
      !if ver_02 = 1 {
                pla
                tax
      } else { ;ver_02 = 0
                plx
      } ;ver_02 = 1
    } ;aligned_read = 0 and (enable_write = 1 or enable_seek = 1)
                pla
                sta     adrlo
                pla
                sta     adrhi
  } ;allow_trees = 1

                ;fetch data block and read/write it

skiptree        ldy     blkidx
+               inc     blkidx
  !if aligned_read = 0 {
    !if enable_seek = 1 {
                txa ;cpx #cmdseek, but that would require php at top
                beq     +
    } ;enable_seek = 1
    !if enable_write = 1 {
                stx     command
    } ;enable_write = 1
  } ;aligned_read = 0

                ldx     dirbuf, y
                lda     dirbuf + 256, y
  !if detect_treof = 1 {
                bne     noteof2
                tay
                txa
                bne     fixy2
                sec
                rts
fixy2           tya
noteof2
  } ;detect_treof = 1
  !if allow_sparse = 1 {
                pha
                ora     dirbuf, y
                tay
                pla
                dey
                iny ;don't affect carry
  } ;allow_sparse = 1
  !if aligned_read = 0 {
                php
  } ;aligned_read = 0
  !if allow_sparse = 1 {
                beq     issparse
  } ;allow_sparse = 1
  !if (aligned_read and (enable_write or enable_seek)) = 1 {
                ldy     reqcmd
    !if enable_seek = 1 {
                beq     +
    } ;enable_seek = 1
  } ;aligned_read = 1 and (enable_write = 1 or enable_seek = 1)
  !if enable_write = 1 {
                jsr     seekrdwr
  } else { ;enable_write = 0
                jsr     seekrd
  } ;enable_write = 1

resparse
  !if aligned_read = 0 {
                plp
+               bcc     +
    !if bounds_check = 1 {
                dec     blefthi
                dec     blefthi
    } ;bounds_check = 1
  } ;aligned_read = 0
                dec     sizehi
                dec     sizehi
                bne     rdwrloop

  !if aligned_read = 0 {
                lda     sizelo
                bne     rdwrloop
  } ;aligned_read = 0
rdwrdone
  !if no_interrupts = 0 {
unrdrvoff4 = unrelocdsk + (* - reloc)
                lda     MOTOROFF
  } ;no_interrupts = 0
  !if allow_aux = 1 {
                ldx     #0
setaux          sta     CLRAUXRD, x
                sta     CLRAUXWR, x
  } ;allow_aux = 1
                rts

  !if allow_sparse = 1 {
issparse
-               sta     (adrlo), y
                iny
                bne     -
                inc     adrhi
-               sta     (adrlo), y
                iny
                bne     -
                dec     adrhi
                bne     resparse
  } ;allow_sparse = 1

  !if aligned_read = 0 {
                ;cache partial block offset

+               pla
                sta     scratchlo
                pla
                sta     scratchhi
                pla
    !if one_shot = 0 {
                sta     sizehi
    } ;one_shot = 0
                dec     adrhi
                dec     adrhi

    !if enable_seek = 1 {
copycache
                ldy     reqcmd
                ;cpy #cmdseek
                beq     ++
                tay
    } else { ;enable_seek = 0
                tay
copycache
    } ;enable_seek = 1
                beq     +
                dey
-               lda     (adrlo), y
                sta     (scratchlo), y
                iny
                bne     -
                inc     scratchhi
                inc     adrhi
                bne     +
-               lda     (adrlo), y
                sta     (scratchlo), y
                iny
+               cpy     sizelo
                bne     -
++
    !if one_shot = 0 {
      !if bounds_check = 1 {
                lda     bleftlo
                sec
                sbc     sizelo
                sta     bleftlo
                lda     blefthi
                sbc     sizehi
                sta     blefthi
      } ;bounds_check = 1
                clc
      !if enable_seek = 1 {
                lda     sizelo
      } else { ;enable_seek = 0
                tya
      } ;enable_seek = 1
                adc     blkofflo
                sta     blkofflo
                lda     sizehi
                adc     blkoffhi
                and     #$fd
                sta     blkoffhi
                bcc     rdwrdone ;always
    } else { ;one_shot = 1
      !if no_interrupts = 0 {
unrdrvoff5 = unrelocdsk + (* - reloc)
                lda     MOTOROFF
      } ;no_interrupts = 0
                rts
    } ;one_shot = 0
  } ;aligned_read = 0

prepdrive
  !if allow_multi = 1 {
                ldy     #0
  } ;allow_multi = 1
prepdrivei
                jsr     poll
                php

unrdrvon2 = unrelocdsk + (* - reloc)
                lda     MOTORON
  !if allow_multi = 1 {
                asl     reqcmd
                bcc     seldrive
twodrives       nop                     ;replace with INY if drive exists
seldrive        lsr     reqcmd
unrdrvsel2 = unrelocdsk + (* - reloc)
                lda     DRV0EN, y
                cpy     driveind + 1
                beq     nodelay
                sty     driveind + 1
                plp
                ldy     #0
                php

nodelay
  } ;allow_multi = 1
                plp
                bne     +
                jsr     spinup
+
  !if poll_drive = 1 {
                jsr     poll
                bne     +
                pla
                pla
                jmp     nodisk
+
                ; Drive is spinning. See if there's real disk data.
                ldx     #0
                ldy     #0
--              jsr     readnib
-               cmp     #$D5
                beq     +
                inx
                bne     --
                iny
                bne     --
                pla
                pla
                jmp     nodisk
+               jsr     readnib
                cmp     #$AA
                bne     -
                jsr     readnib
                cmp     #$96
                bne     -
  } ;poll_drive = 1
                rts

                ;no tricks here, just the regular stuff

seek            ldy     #0
                sty     step
                asl     phase
                txa
                asl
                sta     tmptrk

copy_cur        lda     tmptrk
                sta     tmpsec
                sec
                sbc     phase
                beq     +++
                bcs     +
                eor     #$ff
                inc     tmptrk
                bcc     ++
+               sbc     #1
                dec     tmptrk
++              cmp     step
                bcc     +
                lda     step
+               cmp     #8
                bcs     +
                tay
                sec
+               jsr     ++++
                lda     step1, y
                jsr     delay
                lda     tmpsec
                clc
                jsr     +++++
                lda     step2, y
                jsr     delay
                inc     step
                bne     copy_cur
+++             jsr     delay
                clc
++++            lda     tmptrk
+++++           and     #3
                rol
                tax

unrseek = unrelocdsk + (* - reloc)
                lda     PHASEOFF, x
                rts

spinup          ldy     #6
-               jsr     delay
                dey
                bpl     -

delay
--              ldx     #$11
-               dex
                bne     -
                inc     scratchlo
                bne     +
                inc     scratchhi
+               sec
                sbc     #1
                bne     --
                rts

step1           !byte   1, $30, $28, $24, $20, $1e, $1d, $1c
step2           !byte   $70, $2c, $26, $22, $1f, $1e, $1d, $1c

readadr
-               jsr     readd5aa
                cmp     #$96
                bne     -
                ldy     #3
-               sta     curtrk
                jsr     readnib
                rol
                sta     tmpsec
                jsr     readnib
                and     tmpsec
                dey
                bne     -
seekret         rts

readd5aa
--              jsr     readnib
-               cmp     #$d5
                bne     --
                jsr     readnib
                cmp     #$aa
                bne     -
                tay ;we need Y=#$AA later

readnib
unrread1 = unrelocdsk + (* - reloc)
-               lda     Q6L
                bpl     -
                rts

poll            ldx     #0
unrread2 = unrelocdsk + (* - reloc)
-               lda     Q6L
                jsr     seekret
                pha
                pla
unrread3 = unrelocdsk + (* - reloc)
                eor     Q6L
                bne     +
                dex
                bne     -
+               rts

readdirsel
  !if (ver_02 + allow_multi) > 0 {
                ldy     #0
                sty     adrlo
    !if poll_drive = 1 {
                sty     status
    } ;poll_drive = 1
  } else { ;ver_02 = 0 and allow_multi = 0
                stz     adrlo
    !if poll_drive = 1 {
                stz     status
    } ;poll_drive = 1
  } ;ver_02 = 1 or allow_multi = 1

readdirsec
  !if allow_trees = 0 {
readdirsect     ldy     #>dirbuf
  } else { ;allow_trees = 1
                ldy     #>dirbuf
readdirsect
  } ;allow_trees = 1
                sty     adrhi
seekrd          ldy     #cmdread
  !if (aligned_read + enable_write) > 1 {
seekrdwr        sty     command
  } else { ;aligned_read = 0 or enable_write = 0
                sty     command
seekrdwr
  } ;aligned_read = 1 and enable_write = 1

                ;convert block number to track/sector

                lsr
                txa
                ror
                lsr
                lsr
                sta     phase
                txa
                and     #3
                php
                asl
                plp
                rol
                sta     reqsec

  !if allow_multi = 1 {
driveind        ldy     #0
                ldx     trackd1, y
  } else { ;allow_multi = 0
trackd1 = * + 1
                ldx     #$d1
  } ;allow_multi = 1

                ;if track does not match, then seek

                cpx     phase
                beq     checksec
                lda     phase
  !if allow_multi = 1 {
                sta     trackd1, y
  } else { ;allow_multi = 0
                sta     trackd1
  } ;allow_multi = 1
                jsr     seek

                ;match or read/write sector

checksec        jsr     cmpsecrd
                inc     reqsec
                inc     reqsec

cmpsecrd        jsr     readadr

  !if enable_write = 1 {
                ldy     command
                cpy     #cmdwrite ;we need Y=2 below
                beq     encsec
  } ;enable_write = 1
                cmp     reqsec
                bne     cmpsecrd

                ;read sector data

                jsr     readd5aa
                eor     #$ad ;zero A if match
                bne     cmpsecrd
unrread4 = unrelocdsk + (* - reloc)
-               ldx     Q6L
                bpl     -
                eor     nibtbl - $96, x
                sta     bit2tbl - $aa, y
                iny
                bne     -
unrread5 = unrelocdsk + (* - reloc)
-               ldx     Q6L
                bpl     -
                eor     nibtbl - $96, x
                sta     (adrlo), y ;the real address
                iny
                bne     -
  !if check_chksum = 1 {
unrread6 = unrelocdsk + (* - reloc)
-               ldx     Q6L
                bpl     -
                eor     nibtbl - $96, x
                bne     cmpsecrd
  } ;check_chksum = 1
--              ldx     #$a9
-               inx
                beq     --
                lda     (adrlo), y
                lsr     bit2tbl - $aa, x
                rol
                lsr     bit2tbl - $aa, x
                rol
                sta     (adrlo), y
                iny
                bne     -
                inc     adrhi
                rts

  !if enable_write = 1 {
encsec
--              ldx     #$aa
-               dey
                lda     (adrlo), y
                lsr
                rol     bit2tbl - $aa, x
                lsr
                rol     bit2tbl - $aa, x
                sta     encbuf, y
                lda     bit2tbl - $aa, x
                and     #$3f
                sta     bit2tbl - $aa, x
                inx
                bne     -
                tya
                bne     --

cmpsecwr        jsr     readadr
                cmp     reqsec
                bne     cmpsecwr

                ;skip tail #$DE #$AA #$EB some #$FFs ...

                ldy     #$24
-               dey
                bpl     -

                ;write sector data

unrslot1 = unrelocdsk + (* - reloc)
                ldx     #$d1
                lda     Q6H, x ;prime drive
                lda     Q7L, x ;required by Unidisk
  !if detect_wp = 1 {
                asl
                ror     status
  } ;detect_wp = 1
                tya
                sta     Q7H, x
                ora     Q6L, x

                ;40 cycles

                ldy     #4             ;2 cycles
                pha                    ;3 cycles
                pla                    ;4 cycles
                nop                    ;2 cycles
loopchk1
-               jsr     writenib1      ;(29 cycles)

                                       ;+6 cycles
                dey                    ;2 cycles
                bne     -              ;3 cycles if taken, 2 if not

                ;36 cycles
                                       ;+10 cycles
                ldy     #(prolog_e - prolog)
                                       ;2 cycles
    !if >loopchk1 != >* {
      !serious "loop1 crosses a page"
    }
                cmp     $ea            ;3 cycles
loopchk2
-               lda     prolog - 1, y  ;4 cycles
                jsr     writenib2      ;(17 cycles)

                ;32 cycles if branch taken
                                       ;+6 cycles
                dey                    ;2 cycles
                bne     -              ;3 cycles if taken, 2 if not

                ;36 cycles on first pass
                                       ;+10 cycles
                tya                    ;2 cycles
    !if >loopchk2 != >* {
      !serious "loop2 crosses a page"
    }
                ldy     #$56           ;2 cycles
loopchk3
-               eor     bit2tbl - 1, y ;5 cycles
                tax                    ;2 cycles
                lda     xlattbl, x     ;4 cycles
unrslot2 = unrelocdsk + (* - reloc)
                ldx     #$d1           ;2 cycles
                sta     Q6H, x         ;5 cycles
                lda     Q6L, x         ;4 cycles

                ;32 cycles if branch taken

                lda     bit2tbl - 1, y ;5 cycles
                dey                    ;2 cycles
                bne     -              ;3 cycles if taken, 2 if not

                ;32 cycles
                                       ;+9 cycles
                clc                    ;2 cycles
    !if >loopchk3 != >* {
      !serious "loop3 crosses a page"
    }
loopchk4
--              eor     encbuf, y      ;4 cycles
loopchk5
-               tax                    ;2 cycles
                lda     xlattbl, x     ;4 cycles
unrslot3 = unrelocdsk + (* - reloc)
                ldx     #$d1           ;2 cycles
                sta     Q6H, x         ;5 cycles
                lda     Q6L, x         ;4 cycles
                bcs     +              ;3 cycles if taken, 2 if not

                ;32 cycles if branch taken

                lda     encbuf, y      ;4 cycles
loopchk6 ;belongs to the "bcs +" above
                iny                    ;2 cycles
                bne     --             ;3 cycles if taken, 2 if not

                ;32 cycles
                                       ;+10 cycles
                sec                    ;2 cycles
    !if >loopchk4 != >* {
      !serious "loop4 crosses a page"
    }
                bcs     -              ;3 cycles

                ;32 cycles
                                       ;+3 cycles
    !if >loopchk6 != >* {
      !serious "loop6 crosses a page"
    }
+               ldy     #(epilog_e - epilog)
                                       ;2 cycles
    !if >loopchk5 != >* {
      !serious "loop5 crosses a page"
    }
                nop                    ;2 cycles
                nop                    ;2 cycles
                nop                    ;2 cycles
loopchk7
-               lda     epilog - 1, y  ;4 cycles
                jsr     writenib2      ;(17 cycles)

                ;32 cycles if branch taken
                                       ;+6 cycles
                dey                    ;2 cycles
                bne     -              ;3 cycles if branch taken, 2 if not

                lda     Q7L, x
    !if >loopchk7 != >* {
      !serious "loop7 crosses a page"
    }
                lda     Q6L, x         ;flush final value
                inc     adrhi
                rts

writenib1       jsr     writeret       ;6 cycles
writenib2
unrslot4 = unrelocdsk + (* - reloc)
                ldx     #$d1           ;2 cycles
                sta     Q6H, x         ;5 cycles
                ora     Q6L, x         ;4 cycles
writeret        rts                    ;6 cycles

prolog          !byte   $ad, $aa, $d5
prolog_e
    !if >(prolog - 1) != >(prolog_e - 1) {
      !serious "prologue crosses a page"
    }
epilog          !byte   $ff, $eb, $aa, $de
epilog_e
    !if >(epilog - 1) != >(epilog_e - 1) {
      !serious "epilogue crosses a page"
    }
  } ;enable_write = 1
codeend
  !if allow_multi = 1 {
trackd1         !byte   0
trackd2         !byte   0
  } ;allow_multi = 1
bit2tbl         = (* + 255) & -256
nibtbl          = bit2tbl + 86
  !if enable_write = 1 {
xlattbl         = nibtbl + 106
dataend         = xlattbl + 64
  } else { ;enable_write = 0
dataend         = nibtbl + 106
  } ;enable_write = 1
} ;enable_floppy = 1
} ;reloc

unrelochdd
!pseudopc reloc {
!if rwts_mode = 1 {
  !if swap_zp = 1 {
                sta     zp_array + namhi - first_zp
                sty     zp_array + namlo - first_zp
                jsr     swap_zpg
  } else { ;swap_zp = 0
                sta     namhi
                sty     namlo
  } ;swap_zp = 1

loopsect
  !if ver_02 = 1 {
                lda     #0
                sta     sizehi
  } else { ;ver_02
                stz     sizehi
  } ;ver_02 = 1
  !if enable_format = 1 {
                ldy     #$0c ;command
                lda     (namlo),y
                cmp     #2 ;write (or format if greater)
                php
                bcc     skipinit ;read
                beq     skipinit ;write
                ldy     #5 ;sector
    !if ver_02 = 1 {
                txa
    } else { ;ver_02
                lda     #0
    } ;ver_02 = 1
                sta     (namlo),y
                dey ;track
                sta     (namlo),y
skipinit
  } ;enable_format = 1
  !if allow_multi = 1 {
                ldy     #3 ;volume
                lda     (namlo),y
    !if allow_zerovol = 1 {
                bne     +
lastvol = * + 1
                lda     #D1S1
+               sta     lastvol
    } ;allow_zerovol = 1
                ldy     #$0e ;returned volume
                sta     (namlo),y
                ldx     #vollist_e-vollist_b
-               dex
                cmp     vollist_b,x
                bne     -
  } ;allow_multi = 1
                ldy     #4 ;track
                lda     (namlo),y
                asl
                asl
                asl
                rol     sizehi
                asl
                rol     sizehi
                iny ;sector
                ora     (namlo),y
  !if allow_multi = 1 {
                ldy     sizehi
-               dex
                bmi     ++
                clc
                adc     #$30
                bcc     +
                iny
+               iny
                iny
                bne     -
++
  } ;allow_multi = 1
  !if allow_trees = 1 {
                tax
    !if allow_multi = 1 {
                tya
    } else { ;allow_multi = 0
                lda     sizehi
    } ;allow_multi = 1
                lsr
                sta     treeidx
                txa
  } else { ;allow_trees = 0
                lsr     sizehi
  } ;allow_trees = 1
                ror
                php
                jsr     seek1
                plp
  !if fast_subindex = 0 {
                lda     #>hddencbuf
                adc     #0
                sta     adrhi
  } else { ;fast_subindex = 1
                bcc     +
                inc     adrhi
+
  } ;fast_subindex = 0
                ldy     #9 ;adrhi
                lda     (namlo),y
                sta     scratchhi
                dey ;adrlo
                lda     (namlo),y
                sta     scratchlo
  !if enable_format = 1 {
                ldy     #0
                ldx     #0
                plp
                bcs     runinit
  } else { ;enable_format = 0
    !if enable_write = 1 {
                ldy     #$0c ;command
                lda     (namlo),y
      !if enable_seek = 1 {
        !if swap_zp = 0 {
                beq     +
        } else { ;swap_zp = 1
                beq     swap_zpg
        } ;swap_zp = 0
      } ;enable_seek
                ldy     #0
                lsr
                bne     runinit
    } else { ;enable_write = 0
                ldy     #0
    } ;enable_write = 1
  } ;enable_format = 1

-               lda     (adrlo),y
                sta     (scratchlo),y
                iny
                bne     -
  !if swap_zp = 0 {
+               clc
                rts
  } else { ;swap_zp = 1
    !if enable_write = 1 {
                beq     swap_zpg
    } ;enable_write = 1
  } ;swap_zp = 0

  !if enable_write = 1 {
runinit
    !if enable_format = 1 {
                bne     format
    } ;enable_format = 1
    !if write_sparse = 1 {
                lda     sparseblk
                beq     writesparse
    } ;write_sparse = 1
-               lda     (scratchlo),y
                sta     (adrlo),y
                iny
                bne     -
    !if write_sparse = 0 {
                lda     #>hddencbuf
                sta     adrhi
                ldy     #cmdwrite
unrcommand1 = unrelochdd + (* - reloc)
                sty     command
      !if use_smartport = 1 {
                nop ;allow replacing "sty command" with "sty pcommand" in extended SmartPort mode
      } ;use_smartport = 1
      !if swap_zp = 1 {
                jsr     hddwriteimm
        !if enable_format = 1 {
                bcc     swap_zpg ;always
        } ;enable_format = 1
      } else { ;swap_zp = 0
                jmp     hddwriteimm
      } ;swap_zp = 1
      !if enable_format = 1 {
clrcarry        clc
                inc     adrhi
format          lda     blanksec,x
                sta     (adrlo),y
                inx
                txa
                and     #7
                tax
                iny
                bne     format
                bcs     clrcarry
                dex
                stx     lasttree
                iny
                lda     #$18 ;blocks
                sta     namlo
                sty     namhi
                lda     #>hddencbuf
                sta     adrhi
                lda     #cmdwrite
                sta     reqcmd
                inc     lastblk ;force mismatch
-               jsr     hddrdwrloop
                inc     blkidx
                bne     +
                inc     treeidx
+               dec     namlo
                bne     -
                dec     namhi
                bpl     -
      } ;enable_format = 1
    } else { ;write_sparse = 1
      !if swap_zp = 1 {
                jsr     hddwriteenc
      } else { ;swap_zp = 0
                jmp     hddwriteenc
      } ;swap_zp = 1
    } ;write_sparse = 0
  } ;enable_write = 1

  !if swap_zp = 1 {
swap_zpg        ldx     #(last_zp - first_zp)
-               lda     first_zp,x
                ldy     zp_array,x
                sta     zp_array,x
                sty     first_zp,x
                dex
                bpl     -
  } ;swap_zp = 1

  !if (enable_write + swap_zp) > 0 {
                clc
                rts
  } ;enable_write = 1 or swap_zp = 1

  !if enable_format = 1 {
blanksec        !text   "SAN INC."
  } ;enable_format = 1

  !if write_sparse = 1 {
writesparse     ldx     #2
                tya
    !if fast_subindex = 0 {
                jsr     hddreaddirsec
    } else { ;fast_subindex = 1
                ldy     #>hddencbuf
                jsr     hddreaddirsect
    } ;fast_subindex = 0
    !if ver_02 = 1 {
                lda     #0
                sta     sizelo
                sta     sizehi
    } else { ;ver_02 = 0
                stz     sizelo
                stz     sizehi
    } ;ver_02 = 1

                ;round up to block count

                lda     hddencbuf + $29
                adc     #$ff
                lda     hddencbuf + $2A
                adc     #1
                lsr
                sta     ldrhi
                ldx     hddencbuf + $27
                lda     hddencbuf + $28
---             ldy     #>hddencbuf
                sty     adrhi
                jsr     hddseekrd
                ldy     #0

                ;scan for a free block

--              lda     #$80
                sta     ldrlo
-               lda     (adrlo), y
                and     ldrlo
                bne     foundbit
                inc     sizelo
                lsr     ldrlo
                bcc     -
                lda     sizelo
                bne     +
                inc     sizehi
+               iny
                bne     --
                inc     adrhi
                lda     adrhi
                cmp     #(>hddencbuf) + 2
                bne     --
unrbloklo2 = unrelochdd + (* - reloc)
                ldx     bloklo
    !if use_smartport = 1 {
                nop ;allow replacing "ldx bloklo" with "ldx pblock" in extended SmartPort mode
    } ;use_smartport = 1

                inx
                bne     +
unrblokhi2 = unrelochdd + (* - reloc)
                inc     blokhi
    !if use_smartport = 1 {
                nop ;allow replacing "inc blokhi" with "inc pblock + 1" in extended SmartPort mode
    } ;use_smartport = 1
+
unrblokhi3 = unrelochdd + (* - reloc)
                lda     blokhi
    !if use_smartport = 1 {
                nop ;allow replacing "lda blokhi" with "lda pblock + 1" in extended SmartPort mode
    } ;use_smartport = 1
                dec     ldrhi
                bne     ---

                ;disk full

    !if swap_zp = 0 {
                clc
                rts
    } else { ;swap_zp = 1
                beq     swap_zpg
    } ;swap_zp = 0

                ;allocate block and update bitmap

foundbit        lda     (adrlo), y
                eor     ldrlo
                sta     (adrlo), y
                jsr     hddwriteenc
                inc     lasttree
                lda     #$60 ;RTS
                sta     hddskiptree + 2
                jsr     hddrdfile
                lda     #$be ;LDX ,Y
                sta     hddskiptree + 2
                lda     sizelo
                sta     hdddirbuf, y
                lda     sizehi
                sta     hdddirbuf + 256, y
                jsr     hddwritedir
                lda     #0
                jsr     savebyte
                ldx     sizelo
                lda     sizehi
                ldy     #cmdwrite
                jsr     hddseekrdwr
                jmp     loopsect

hddwriteenc     lda     #>hddencbuf
                sta     adrhi
hddwritedir     ldy     #cmdwrite

unrcommand1 = unrelochdd + (* - reloc)
                sty     command
    !if use_smartport = 1 {
                nop ;allow replacing "sty command" with "sty pcommand" in extended SmartPort mode
    } ;use_smartport = 1
                bne     hddwriteimm
  } ;write_sparse = 1

seek1           sta     blkidx
  !if enable_write = 1 {
                ldy     #cmdread
                sty     reqcmd
  } ;enable_write = 1
} else { ;rwts_mode = 0
  !if (enable_readseq + allow_subdir) > 0 {
hddrdwrpart     jmp     hddrdwrfile
  } ;enable_readseq = 1 or allow_subdir = 1
  !if enable_floppy = 1 {
    !if (* - reloc) < (unrblocklo - unrelocdsk) {
                ;essential padding to match offset with floppy version
      !fill (unrblocklo - unrelocdsk) - (* - reloc), $ea
    }
  } ;enable_floppy = 1

                ;read volume directory key block
                ;self-modified by init code

hddopendir
unrhddblocklo = unrelochdd + (* - reloc)
                ldx     #2
unrhddblockhi = unrelochdd + (* - reloc)
                lda     #0
                jsr     hddreaddirsel

hddreaddir
  !if might_exist = 1 {
                lda     hdddirbuf + FILE_COUNT ;assuming only 256 files per subdirectory
                sta     entries
    !if many_files = 1 {
                lda     hdddirbuf + FILE_COUNT + 1
                sta     entrieshi
    } ;many_files = 1
  } ;might_exist = 1

                lda     #NAME_LENGTH + ENTRY_SIZE
hddfirstent     sta     scratchlo
                lda     #>(hdddirbuf - 1)
                sta     scratchhi

                ;there can be only one page crossed, so we can increment here

hddnextent1     inc     scratchhi
hddnextent      ldy     #0
  !if (might_exist + allow_subdir + allow_saplings + (allow_trees xor always_trees)) > 0 {
                lda     (scratchlo), y
    !if might_exist = 1 {
                sty     status

                ;skip deleted entries without counting

                and     #MASK_ALL
                beq     +
    } ;might_exist = 1

    !if (allow_subdir + allow_saplings + (allow_trees xor always_trees)) > 0 {
                ;remember type
                ;now bits 5-4 are represented by carry (subdirectory), sign (sapling)

                asl
                asl

      !if allow_trees = 1 {
                ;now bits 5-3 are represented by carry (subdirectory), sign (sapling),
                ;overflow (seedling), and sign+overflow (tree)

                sta     treeidx
                bit     treeidx
      } ;allow_trees = 1
                php
    } ;allow_subdir = 1 or allow_saplings = 1 or (allow_trees = 1 and always_trees = 0)
  } ;might_exist = 1 or allow_subdir = 1 or allow_saplings = 1 or (allow_trees = 1 and always_trees = 0)

                ;match name lengths before attempting to match names

                lda     (scratchlo), y
                and     #$0f
                tax
                inx
-               cmp     (namlo), y
                beq     hddfoundname

                ;match failed, check if any directory entries remain

  !if (allow_subdir + allow_saplings + (allow_trees xor always_trees)) > 0 {
                plp
  } ;allow_subdir = 1 or allow_saplings = 1 or (allow_trees = 1 and always_trees = 0)
  !if might_exist = 1 {
                dec     entries
                bne     +
    !if many_files = 1 {
                lda     entrieshi
                bne     ++
    } ;many_files = 1
                inc     status
                rts

    !if many_files = 1 {
++              dec     entrieshi
    } ;many_files = 1
  } ;might_exist = 1

                ;move to next entry in this block, if possible

+               clc
                lda     scratchlo
                adc     #ENTRY_SIZE
                sta     scratchlo
                bcs     hddnextent1
                cmp     #$ff ;4 + ($27 * $0d)
                bne     hddnextent

                ;read next directory block when we reach the end of this block

                ldx     hdddirbuf + NEXT_BLOCK_LO
                lda     hdddirbuf + NEXT_BLOCK_HI
                jsr     hddreaddirsec
                lda     #NAME_LENGTH
                bne     hddfirstent

hddfoundname    iny
                lda     (scratchlo), y
                dex
                bne     -

                ;initialise essential variables

  !if allow_trees = 1 {
                stx     treeidx
    !if always_trees = 0 {
                stx     istree
    } ;always_trees = 0
  } ;allow_trees = 1
                stx     blkidx
  !if (aligned_read + one_shot) = 0 {
                stx     blkofflo
                stx     blkoffhi
  } ;aligned_read = 0 and one_shot = 0
  !if enable_write = 1 {
    !if aligned_read = 0 {
                ldy     reqcmd
                cpy     #cmdwrite ;control carry instead of zero
      !if one_shot = 0 {
                bne     +
      } ;one_shot = 0
    } ;aligned_read = 0
    !if one_shot = 0 {

                ;round requested size up to nearest block if writing

                lda     sizelo
                adc     #$fe
                lda     sizehi
                adc     #1
                and     #$fe
                sta     sizehi
      !if aligned_read = 0 {
                stx     sizelo
        !if bounds_check = 1 {
                sec
        } ;bounds_check = 1
      } ;aligned_read = 0
    } ;one_shot = 0
+
  } ;enable_write = 1

  !if (bounds_check + return_size + one_shot) > 0 {
                ;cache EOF (file size, loaded backwards)

                ldy     #EOF_HI
                lda     (scratchlo), y
    !if (enable_write + aligned_read) > 0 {
                tax
                dey ;EOF_LO
                lda     (scratchlo), y

                ;round file size up to nearest block if writing without aligned reads
                ;or always if using aligned reads

      !if aligned_read = 0 {
                bcc     +
      } else { ;aligned_read = 1
        !if (enable_write + (one_shot xor 1)) > 1 {
                sec
        } ;enable_write = 1 and one_shot = 0
      } ;aligned_read = 0
                adc     #$fe
                txa
                adc     #1
                and     #$fe
      !if aligned_read = 0 {
                tax
                lda     #0
        !if one_shot = 0 {
+               stx     blefthi
                sta     bleftlo
        } else { ;one_shot = 1
+               stx     sizehi
                sta     sizelo
        } ;one_shot = 0
      } else { ;aligned_read = 1
        !if one_shot = 0 {
                sta     blefthi
        } else { ;one_shot = 1
                sta     sizehi
        } ;one_shot = 0
      } ;aligned_read = 0
    } else { ;enable_write = 0 and aligned_read = 0
      !if one_shot = 0 {
                sta     blefthi
      } else { ;one_shot = 1
                sta     sizehi
      } ;one_shot = 0
                dey ;EOF_LO
                lda     (scratchlo), y
      !if one_shot = 0 {
                sta     bleftlo
      } else { ;one_shot = 1
                sta     sizelo
      } ;one_shot = 0
    } ;enable_write = 1 or aligned_read = 1
  } ;bounds_check = 1 or return_size = 1 or one_shot = 1
                ;cache AUX_TYPE (load offset for binary files)

  !if override_adr = 0 {
                ldy     #AUX_TYPE
                lda     (scratchlo), y
    !if (allow_subdir + allow_saplings + allow_trees + (aligned_read xor 1)) > 0 {
                sta     ldrlo
                iny
                lda     (scratchlo), y
                sta     ldrhi
    } else { ;allow_subdir = 0 and allow_saplings = 0 and allow_trees = 0 and aligned_read = 1
                pha
                iny
                lda     (scratchlo), y
                pha
    } ;allow_subdir = 1 or allow_saplings = 1 or allow_trees = 1 or aligned_read = 0
  } ;override_adr = 0

                ;cache KEY_POINTER

                ldy     #KEY_POINTER
                lda     (scratchlo), y
                tax
  !if (allow_subdir + allow_saplings + allow_trees) > 0 {
                sta     hdddirbuf
    !if (allow_trees + (fast_trees xor 1)) > 1 {
                sta     treeblklo
    } ;allow_trees = 1 and fast_trees = 0
                iny
                lda     (scratchlo), y
                sta     hdddirbuf + 256
    !if (allow_trees + (fast_trees xor 1)) > 1 {
                sta     treeblkhi
    } ;allow_trees = 1 and fast_trees = 0

    !if (allow_saplings + write_sparse) > 1 {
                ;clear dirbuf in case sparse sapling becomes seedling

                pha
                ldy     #1
                lda     #0
-               sta     hdddirbuf, y
                sta     hdddirbuf + 256, y
                iny
                bne     -
                pla
    } ;allow_saplings = 1 and write_sparse = 1

    !if always_trees = 0 {
                plp
                bpl     ++
      !if allow_subdir = 1 {
                php
      } ;allow_subdir = 1
      !if allow_trees = 1 {
                ldy     #>hdddirbuf
                bvc     +
        !if fast_trees = 1 {
                ldy     #>hddtreebuf
        } ;fast_trees = 1
                sty     istree
+
      } ;allow_trees = 1
    } else { ;always_trees = 1
                ldy     #>hddtreebuf
    } ;always_trees = 0
  } else { ;allow_subdir = 0 and allow_saplings = 0 and allow_trees = 0
                iny
                lda     (scratchlo), y
  } ;allow_subdir = 1 or allow_saplings = 1 or allow_trees = 1

                ;read index block in case of sapling or tree

                jsr     hddreaddirsect

  !if allow_subdir = 1 {
                plp
                !byte  $24 ;mask the clc that follows
  } else { ;allow_subdir = 0
++
  } ;allow_subdir = 1
} ;rwts_mode = 1

hddrdfile
hddrdwrfile
!if allow_subdir = 1 {
                clc
++
} ;allow_subdir = 1

hddrdwrfilei
!if rwts_mode = 0 {
  !if (override_adr + allow_subdir + allow_saplings + allow_trees + (aligned_read xor 1)) > 0 {
                ;restore load offset

                ldx     ldrhi
                lda     ldrlo
    !if allow_subdir = 1 {
                ;check file type and fake size and load address for subdirectories

                bcc     +
                ldy     #2
                sty     sizehi
                ldx     #>hdddirbuf
                lda     #0
      !if aligned_read = 0 {
                sta     sizelo
      } ;aligned_read = 0
+
    } ;allow_subdir = 1
                sta     adrlo
                stx     adrhi
  } else { ;override_adr = 0 and allow_subdir = 0 and allow_saplings = 0 and allow_trees = 0 and aligned_read = 1
                pla
                sta     adrhi
                pla
                sta     adrlo
  } ;override_adr = 1 or allow_subdir = 1 or allow_saplings = 1 or allow_trees = 1 or aligned_read = 0

                ;set requested size to min(length, requested size)

  !if aligned_read = 0 {
    !if bounds_check = 1 {
                ldy     bleftlo
                cpy     sizelo
                lda     blefthi
                tax
                sbc     sizehi
                bcs     hddcopyblock
                sty     sizelo
                stx     sizehi
    } ;bounds_check = 1

hddcopyblock
    !if allow_aux = 1 {
                ldx     auxreq
                jsr     hddsetaux
    } ;allow_aux = 1
    !if one_shot = 0 {
      !if enable_write = 1 {
                lda     reqcmd
                lsr
                bne     hddrdwrloop
      } ;enable_write = 1

                ;if offset is non-zero then we return from cache

                lda     blkofflo
                tax
                ora     blkoffhi
                beq     hddrdwrloop
                lda     sizehi
                pha
                lda     sizelo
                pha
                lda     adrhi
                sta     scratchhi
                lda     adrlo
                sta     scratchlo
                stx     adrlo
                lda     #>hddencbuf
                clc
                adc     blkoffhi
                sta     adrhi

                ;determine bytes left in block

                lda     #1
                sbc     blkofflo
                tay
                lda     #2
                sbc     blkoffhi
                tax

                ;set requested size to min(bytes left, requested size)

                cpy     sizelo
                sbc     sizehi
                bcs     +
                sty     sizelo
                stx     sizehi
+
      !if enable_seek = 1 {
                lda     sizehi
        !if read_scrn = 1 {
                clv
        } ;read_scrn = 1
      } else { ;enable_seek = 0
                ldy     sizehi
      } ;enable_seek = 1
                jsr     hddcopycache

                ;align to next block and resume read

                lda     ldrlo
                adc     sizelo
                sta     ldrlo
                lda     ldrhi
                adc     sizehi
                sta     ldrhi
                sec
                pla
                sbc     sizelo
                sta     sizelo
                pla
                sbc     sizehi
                sta     sizehi
                ora     sizelo
      !if allow_subdir = 1 {
                bne     hddrdwrfile
      } else { ;allow_subdir = 0
                bne     hddrdwrfilei
      } ;allow_subdir = 1
      !if no_interrupts = 1 {
                clc
      } ;no_interrupts = 1
      !if allow_aux = 0 {
                rts
      } else { ;allow_aux = 1
                beq     hddrdwrdone
      } ;allow_aux = 0
    } ;one_shot = 0
  } else { ;aligned_read = 1
    !if bounds_check = 1 {
                lda     blefthi
                cmp     sizehi
                bcs     +
                sta     sizehi
+
    } ;bounds_check = 1
    !if allow_aux = 1 {
                ldx     auxreq
                jsr     hddsetaux
    } ;allow_aux = 1
  } ;aligned_read = 0
} ;rwts_mode = 0

hddrdwrloop
!if (aligned_read + rwts_mode) = 0 {
  !if (enable_write + enable_seek) > 0 {
                ldx     reqcmd
  } ;enable_write = 1 or enable_seek = 1

                ;set read/write size to min(length, $200)

                lda     sizehi
                cmp     #2
  !if read_scrn = 1 {
                clv
                bcc     redirect
                txa
                beq     +
                ldy     ldrhi
                cpy     #8
                bcs     +
                bit     knownrts ;set O flag
                lda     sizehi
                pha
                lda     sizelo
                pha
                txa
                dex
                stx     sizelo

redirect
  } else { ;read_scrn = 0
                bcs     +
  } ;read_scrn = 1
                pha

                ;redirect read to private buffer for partial copy

                lda     adrhi
                pha
                lda     adrlo
                pha
                lda     #>hddencbuf
                sta     adrhi
  !if ver_02 = 1 {
                ldx     #0
                stx     adrlo
    !if (enable_write + enable_seek) > 0 {
                inx ;ldx #cmdread
    } ;enable_write = 1 or enable_seek = 1
  } else { ;ver_02 = 0
                stz     adrlo
    !if (enable_write + enable_seek) > 0 {
                ldx     #cmdread
    } ;enable_write = 1 or enable_seek = 1
  } ;ver_02 = 1
+
} ;aligned_read = 0 and rwts_mode = 0

!if allow_trees = 1 {
                ;read tree data block only if tree and not read already
                ;the indication of having read already is that at least one sapling/seed block entry has been read, too

  !if rwts_mode = 0 {
                ldy     blkidx
                bne     +
    !if always_trees = 0 {
                lda     istree
                beq     +
    } ;always_trees = 0
                lda     adrhi
                pha
                lda     adrlo
                pha
    !if ((aligned_read xor 1) + (enable_write or enable_seek)) > 1 {
      !if ver_02 = 1 {
                txa
                pha
      } else { ;ver_02 = 0
                phx
      } ;ver_02 = 1
    } ;aligned_read = 0 and (enable_write = 1 or enable_seek = 1)
    !if aligned_read = 0 {
                php
    } ;aligned_read = 0
                lda     #>hdddirbuf
                sta     adrhi
                sty     adrlo
  } else { ;rwts_mode = 1
    !if fast_subindex = 0 {
                ;read whenever block index changes

      !if mem_swap = 0 {
                cmp     lastblk
                sta     lastblk
      } else { ;mem_swap = 1
blkidx = * + 1
                ldy     #$d1
lastblk = * + 1
                cpy     #$d1
                sty     lastblk
      } ;mem_swap = 0
                php
                pla
      !if mem_swap = 0 {
                ;read whenever tree index changes

                ldy     treeidx
                cpy     lasttree
      } else { ;mem_swap = 1
treeidx = * + 1
                ldy     #$d1
lasttree = * + 1
                cpy     #$d1
      } ;mem_swap = 0
    
                sty     lasttree
                bne     readtree
                pha
                plp
      !if enable_write = 1 {
                bne     readtree
                lda     reqcmd
                lsr
      } ;enable_write = 1
                beq     skipblk

readtree
    } else { ;fast_subindex = 1
                ;read whenever tree index changes

      !if mem_swap = 0 {
                ldy     treeidx
                cpy     lasttree
                beq     hddskiptree
                sty     lasttree
                ldx     blkidx
      } else { ;mem_swap = 1
treeidx = * + 1
                ldy     #$d1
lasttree = * + 1
                cpy     #$d1
                beq     hddskiptree
                sty     lasttree
blkidx = * + 1
                ldx     #$d1
      } ;mem_swap = 0
                inx
                stx     lastblk
    } ;fast_subindex = 0
  } ;rwts_mode = 0

                ;fetch tree data block and read it

  !if fast_trees = 0 {
                ldx     treeblklo
                lda     treeblkhi
                jsr     hddreaddirsel
                ldy     treeidx
    !if rwts_mode = 0 {
                inc     treeidx
    } ;rwts_mode = 0
                ldx     hdddirbuf, y
                lda     hdddirbuf + 256, y
  } else { ;fast_trees = 1
                ldy     treeidx
    !if rwts_mode = 0 {
                inc     treeidx
    } ;rwts_mode = 0
                ldx     hddtreebuf, y
                lda     hddtreebuf + 256, y
  } ;fast_trees = 0
  !if detect_treof = 1 {
                bne     hddnoteof1
                tay
                txa
                bne     hddfixy1
    !if aligned_read = 0 {
                plp
                bcs     hddfewpop
                pla
                pla
                pla
hddfewpop
    } ;aligned_read = 0
                pla
                pla
                sec
                rts
hddfixy1        tya
hddnoteof1
  } ;detect_treof = 1

  !if fast_trees = 0 {
                jsr     hddseekrd
  } else { ;fast_trees = 1
                jsr     hddreaddirsel
  } ;fast_trees = 0

  !if rwts_mode = 0 {
    !if aligned_read = 0 {
                plp
    } ;aligned_read = 0
    !if ((aligned_read xor 1) + (enable_write or enable_seek)) > 1 {
      !if ver_02 = 1 {
                pla
                tax
      } else { ;ver_02 = 0
                plx
      } ;ver_02 = 1
    } ;aligned_read = 0 and (enable_write = 1 or enable_seek = 1)
                pla
                sta     adrlo
                pla
                sta     adrhi
  } ;rwts_mode = 0
} ;allow_trees = 1

                ;fetch data block and read/write it

hddskiptree     ldy     blkidx
!if rwts_mode = 0 {
+               inc     blkidx
  !if aligned_read = 0 {
    !if enable_seek = 1 {
                txa ;cpx #cmdseek, but that would require php at top
                beq     +
    } ;enable_seek = 1
    !if enable_write = 1 {
unrcommand2 = unrelochdd + (* - reloc)
                stx     command
      !if use_smartport = 1 {
                nop ;allow replacing "stx command" with "stx pcommand" in extended SmartPort mode
      } ;use_smartport = 1
    } ;enable_write = 1
  } ;aligned_read = 0
} else { ;rwts_mode = 1
  !if fast_subindex = 1 {
                lda     #>hddencbuf
                sta     adrhi

                ;read whenever block index changes

    !if mem_swap = 0 {
                cpy     lastblk
    } else { ;mem_swap = 1
lastblk = * + 1
                cpy     #$d1
    } ;mem_swap = 0
    !if enable_write = 0 {
                beq     skipblk
    } else { ;enable_write = 1
                bne     +
                lda     reqcmd
                lsr
                beq     skipblk
+
    } ;enable_write = 0
                sty     lastblk
  } ;fast_subindex = 1
} ;rwts_mode = 0
                ldx     hdddirbuf, y
                lda     hdddirbuf + 256, y
!if detect_treof = 1 {
                bne     hddnoteof2
                tay
                txa
                bne     hddfixy2
                sec
                rts
hddfixy2        tya
hddnoteof2
} ;detect_treof = 1
!if allow_sparse = 0 {
  !if rwts_mode = 1 {
    !if enable_write = 0 {
                jmp     hddseekrd
    } else { ;enable_write = 1
                ldy     reqcmd
      !if enable_seek = 1 {
                jmp     hddseekrdwr
      } else { ;enable_seek = 0
                bne     hddseekrdwr
      } ;enable_seek = 1
    } ;enable_write = 0
  } ;rwts_mode = 1
} else { ;allow_sparse = 1
                pha
                ora     hdddirbuf, y
  !if write_sparse = 1 {
                sta     sparseblk
  } ;write_sparse = 1
  !if (rwts_mode + enable_write) > 1 {
                cmp     #1
  } else { ;rwts_mode = 0 or enable_write = 0
                tay
  } ;rwts_mode = 1 and enable_write = 1
                pla
  !if rwts_mode = 0 {
                dey
                iny ;don't affect carry
  } else { ;rwts_mode = 1
    !if enable_write = 1 {
                ldy     reqcmd
                bcs     hddseekrdwr
savebyte
                tay
    } else { ;enable_write = 0
                dey
                iny ;don't affect carry
                bne     hddseekrd
    } ;enable_write = 1
  } ;rwts_mode = 0
} ;allow_sparse = 0
!if rwts_mode = 0 {
  !if aligned_read = 0 {
                php
  } ;aligned_read = 0
  !if allow_sparse = 1 {
                beq     hddissparse
  } ;allow_sparse = 1
  !if (aligned_read and (enable_write or enable_seek)) = 1 {
                ldy     reqcmd
    !if enable_seek = 1 {
                beq     +
    } ;enable_seek = 1
  } ;aligned_read = 1 and (enable_write = 1 or enable_seek = 1)
  !if enable_write = 1 {
                jsr     hddseekrdwr
  } else { ;enable_write = 0
                jsr     hddseekrd
  } ;enable_write = 1

hddresparse
  !if aligned_read = 0 {
                plp
+               bcc     +
  } ;aligned_read = 0
                inc     adrhi
                inc     adrhi
  !if aligned_read = 0 {
resumescrn
    !if bounds_check = 1 {
                dec     blefthi
                dec     blefthi
    } ;bounds_check = 1
  } ;aligned_read = 0
                dec     sizehi
                dec     sizehi
                bne     hddrdwrloop
  !if aligned_read = 0 {
                lda     sizelo
                bne     hddrdwrloop
  } ;aligned_read = 0
hddrdwrdone
  !if allow_aux = 1 {
                ldx     #0
hddsetaux       sta     CLRAUXRD, x
                sta     CLRAUXWR, x
  } ;allow_aux = 1
                rts
} ;rwts_mode = 0

!if allow_sparse = 1 {
hddissparse
-               sta     (adrlo), y
                inc     adrhi
                sta     (adrlo), y
                dec     adrhi
                iny
                bne     -
  !if rwts_mode = 0 {
                beq     hddresparse
  } else { ;rwts_mode = 1
skipblk         rts
  } ;rwts_mode = 0
} ;allow_sparse = 1
!if rwts_mode = 0 {
  !if aligned_read = 0 {
                ;cache partial block offset

+               pla
                sta     scratchlo
                pla
                sta     scratchhi
                pla
    !if one_shot = 0 {
                sta     sizehi
    } ;one_shot = 0

    !if enable_seek = 1 {
hddcopycache
                ldy     reqcmd
                ;cpy #cmdseek
                beq     ++
                tay
    } else { ;enable_seek = 0
                tay
hddcopycache
    } ;enable_seek = 1
                beq     +
                dey
-               lda     (adrlo), y
                sta     (scratchlo), y
                iny
                bne     -
                inc     scratchhi
                inc     adrhi
    !if read_scrn = 1 {
                bvs     copyhalf
    } ;read_scrn = 1
                bne     +
copyhalf
-               lda     (adrlo), y
                sta     (scratchlo), y
                iny
+               cpy     sizelo
                bne     -
    !if read_scrn = 1 {
                bvc     ++
                pla
                sta     sizelo
                pla
                sta     sizehi
                ldx     scratchhi
                inx
                stx     adrhi
                lda     scratchlo
                sta     adrlo
                bvs     resumescrn
    } ;read_scrn = 1
++
    !if one_shot = 0 {
      !if bounds_check = 1 {
                lda     bleftlo
                sec
                sbc     sizelo
                sta     bleftlo
                lda     blefthi
                sbc     sizehi
                sta     blefthi
      } ;bounds_check = 1
                clc
      !if enable_seek = 1 {
                lda     sizelo
      } else { ;enable_seek = 0
                tya
      } ;enable_seek = 1
                adc     blkofflo
                sta     blkofflo
                lda     sizehi
                adc     blkoffhi
                and     #$fd
                sta     blkoffhi
                bcc     hddrdwrdone ;always
    } else { ;one_shot = 1
      !if allow_aux = 1 {
                beq     hddrdwrdone
      } else { ;allow_aux = 0
                rts
      } ;allow_aux = 1
    } ;one_shot = 0
  } ;aligned_read = 0
} ;rwts_mode = 0

hddreaddirsel
!if ver_02 = 1 {
                ldy     #0
                sty     adrlo
  !if might_exist = 1 {
                sty     status
  } ;might_exist = 1
} else { ;ver_02 = 0
                stz     adrlo
  !if might_exist = 1 {
                stz     status
  } ;might_exist = 1
} ;ver_02 = 1

!if (enable_floppy + allow_multi) > 1 {
                asl     reqcmd
                lsr     reqcmd
} ;enable_floppy = 1 and allow_multi = 1

hddreaddirsec
!if allow_trees = 0 {
hddreaddirsect  ldy     #>hdddirbuf
} else { ;allow_trees = 1
                ldy     #>hdddirbuf
hddreaddirsect
} ;allow_trees = 0
                sty     adrhi
hddseekrd       ldy     #cmdread
!if ((rwts_mode or aligned_read) + enable_write) > 1 {
hddseekrdwr
} ;(rwts_mode = 1 or aligned_read = 1) and enable_write = 1
unrcommand3 = unrelochdd + (* - reloc)
                sty     command
!if use_smartport = 1 {
                nop ;allow replacing "sty command" with "sty pcommand" in extended SmartPort mode
} ;use_smartport = 1
!if (aligned_read and enable_write) = 0 {
hddseekrdwr
} ;aligned_read = 0 or enable_write = 0

unrbloklo1 = unrelochdd + (* - reloc)
                stx     bloklo
!if use_smartport = 1 {
                nop ;allow replacing "stx bloklo" with "stx pblock" in extended SmartPort mode
} ;use_smartport = 1
unrblokhi1 = unrelochdd + (* - reloc)
                sta     blokhi
!if use_smartport = 1 {
                nop ;allow replacing "sta blokhi" with "sta pblock + 1" in extended SmartPort mode
} ;use_smartport = 1
unrunit1 = unrelochdd + (* - reloc)
                lda     #$d1
                sta     unit
!if use_smartport = 1 {
                nop ;allow replacing "lda #$d1/sta unit" with "lda adrlo/sta paddr" in extended SmartPort mode
} ;use_smartport = 1
hddwriteimm     lda     adrhi ;for Trackstar support
                pha
!if use_smartport = 1 {
                sta     paddr + 1
} ;use_smartport = 1
!if swap_scrn = 1 {
                jsr     saveslot
} ;swap_scrn = 1

unrentrysei = unrelochdd + (* - reloc)
!if no_interrupts = 1 {
                php
                sei
} ;no_interrupts = 1
unrentry = unrelochdd + (* - reloc)
                jsr     $d1d1
!if use_smartport = 1 {
unrpcommand = unrelochdd + (* - reloc)
pcommand        !byte   $2c ;hide packet in non-SmartPort mode
unrppacket = unrelochdd + (* - reloc)
                !word   unrelochdd + (packet - reloc)
} ;use_smartport = 1
!if no_interrupts = 1 {
                plp
} ;no_interrupts = 1
hackstar = unrelochdd + (* - reloc)
                pla
                sta     adrhi ;Trackstar does not preserve adrhi

!if swap_scrn = 1 {
saveslot
                lda     #4
                sta     $49
                ldx     #0
                stx     $48
                sta     $4a
--              ldy     #$78
-               lda     ($48), y
                pha
                lda     scrn_array, x
initpatch       lda     ($48), y
                pla
                sta     scrn_array, x
                inx
                tya
                eor     #$80
                tay
                bmi     -
                iny
                bpl     -
                inc     $49
                dec     $4a
                bne     --
} ;swap_scrn = 1
!if (rwts_mode + (allow_sparse xor 1)) > 1 {
skipblk
} ;rwts_mode = 1 and allow_sparse = 0
                rts

!if use_smartport = 1 {
unrpacket = unrelochdd + (* - reloc)
packet          !byte   3
unrunit2 = unrelochdd + (* - reloc)
                !byte   0
paddr           !word   readbuff + $200
pblock          !byte   2, 0, 0
  !if >pcommand != >(pblock + 1) {
    !if >pcommand != >pblock {
      !ifdef pblock_enabled {
      } else {
        !ifdef PASS2 {
          !warn "uncomment ';;lda     #>pblock'"
          !warn "uncomment ';;pblock_enabled=1'"
          !warn "uncomment ';;lda     #>paddr'"
        }
      }
    } else {
      !ifdef pblock1_enabled {
      } else {
        !ifdef PASS2 {
          !warn "uncomment ';;lda     #>(pblock + 1)'"
          !warn "uncomment ';;pblock1_enabled=1'"
          !warn "uncomment ';;lda     #>paddr'"
        }
      }
    }
  }
} ;use_smartport = 1

!if (rwts_mode + allow_multi) > 1 {
vollist_b
!byte D1S1
vollist_e
} ;rwts_mode = 1 and allow_multi = 1
hddcodeend
!if swap_scrn = 1 {
scrn_array
  !if swap_zp = 1 {
zp_array        = scrn_array + 64
hdddataend      = zp_array + 1 + last_zp - first_zp
  } else { ;swap_zp = 0
hdddataend      = scrn_array + 64
  } ;swap_zp = 1
} else { ;swap_scrn = 0
  !if swap_zp = 1 {
zp_array
hdddataend      = zp_array + 1 + last_zp - first_zp
  } else { ;swap_zp = 0
hdddataend
  } ;swap_zp = 1
} ;swap_scrn = 1
} ;reloc

;[music] you can't touch this [music]
;math magic to determine ideal loading address, and information dump
!ifdef PASS2 {
} else { ;PASS2 not defined
  !set PASS2=1
  !if enable_floppy = 1 {
    !if reloc < $c000 {
      !if ((dataend + $ff) & -256) > $c000 {
        !serious "initial reloc too high, adjust to ", $c000 - (((dataend + $ff) & -256) - reloc)
      } ;dataend
      !if load_high = 1 {
        !if ((dataend + $ff) & -256) != $c000 {
          !warn "initial reloc too low, adjust to ", $c000 - (((dataend + $ff) & -256) - reloc)
        } ;dataend
        dirbuf = reloc - $200
        !if ((aligned_read xor 1) + enable_write) > 0 {
          encbuf = dirbuf - $200
        } ;aligned_read = 0 or enable_write = 1
        !if allow_trees = 1 {
          !if fast_trees = 1 {
            !if ((aligned_read xor 1) + enable_write) > 0 {
              treebuf = encbuf - $200
            } else { ;aligned_read = 1 and enable_write = 0
              treebuf = dirbuf - $200
            } ;aligned_read = 0 or enable_write = 1
          } else { ;fast_trees = 0
            treebuf = dirbuf
          } ;fast_trees
        } ;allow_trees
      } else { ;load_high = 0
        !pseudopc ((dataend + $ff) & -256) {
          dirbuf = *
          !if (dirbuf + $200) > $c000 {
            !if dirbuf < $d000 {
              !set dirbuf = reloc - $200
            } ;dirbuf
          } ;dirbuf
        }
        !if ((aligned_read xor 1) + enable_write) > 0 {
          !if fast_subindex = 0 {
            encbuf = dirbuf ;writes come from cache
          } else { ;fast_subindex = 1
            !if dirbuf < reloc {
              encbuf = dirbuf - $200
            } else { ;dirbuf
              encbuf = dirbuf + $200
              !if (encbuf + $200) > $c000 {
                !if encbuf < $d000 {
                  !set encbuf = reloc - $200
                } ;encbuf
              } ;encbuf
            } ;dirbuf
          } ;fast_subindex
        } ;aligned_read = 0 or enable_write = 1
        !if allow_trees = 1 {
          !if fast_trees = 1 {
            !if enable_write = 0 {
              encbuf = dirbuf ;there is no encbuf
            } ;enable_write = 0
            !if ((aligned_read xor 1) + rwts_mode) > 0 {
              !if encbuf < reloc {
                treebuf = encbuf - $200
              } else { ;encbuf
                treebuf = encbuf + $200
                !if (treebuf + $200) > $c000 {
                  !if treebuf < $d000 {
                    !set treebuf = reloc - $200
                  } ;treebuf
                } ;treebuf
              } ;encbuf
            } else { ;aligned_read = 1 and rwts_mode = 0
              !if dirbuf < reloc {
                treebuf = dirbuf - $200
              } else { ;dirbuf
                treebuf = dirbuf + $200
                !if (treebuf + $200) > $c000 {
                  !if treebuf < $d000 {
                    !set treebuf = reloc - $200
                  } ;treebuf
                } ;treebuf
              } ;dirbuf
            } ;aligned_read = 0 or rwts_mode = 1
          } else { ;fast_trees = 0
              treebuf = dirbuf
          } ;fast_trees
        } ;allow_trees
      } ;load_high
    } else { ;reloc > $c000
      !if ((dataend + $ff) & -256) != 0 {
        !if ((dataend + $ff) & -256) < reloc {
          !serious "initial reloc too high, adjust to ", (0 - (((dataend + $ff) & -256) - reloc)) & $ffff
        } ;dataend
      } ;dataend
      !if load_high = 1 {
        !if (((dataend + $ff) & -256) & $ffff) != 0 {
          !warn "initial reloc too low, adjust to ", (0 - (((dataend + $ff) & -256) - reloc)) & $ffff
        } ;dataend
        dirbuf = reloc - $200
        !if aligned_read = 0 {
          encbuf = dirbuf - $200
        } ;aligned_read
        !if allow_trees = 1 {
          !if fast_trees = 1 {
            !if ((aligned_read xor 1) + enable_write) > 0 {
              treebuf = encbuf - $200
            } else { ;aligned_read = 1 and enable_write = 0
              treebuf = dirbuf - $200
            } ;aligned_read = 0 or enable_write = 1
          } else { ;fast_trees = 0
            treebuf = dirbuf
          } ;fast_trees
        } ;allow_trees
      } else { ;load_high = 0
        !pseudopc ((dataend + $ff) & -256) {
          dirbuf = *
        }
        !if ((aligned_read xor 1) + enable_write) > 0 {
          encbuf = dirbuf + $200
        } ;aligned_read = 0 or enable_write = 1
        !if allow_trees = 1 {
          !if fast_trees = 1 {
            !if ((aligned_read xor 1) + enable_write) > 0 {
              treebuf = encbuf + $200
            } else { ;aligned_read = 1 and enable_write = 0
              treebuf = dirbuf + $200
            } ;aligned_read = 0 or enable_write = 1
          } else { ;fast_trees = 0
            treebuf = dirbuf
          } ;fast_trees
        } ;allow_trees
      } ;load_high
    } ;reloc
    !if verbose_info = 1 {
      !warn "floppy code: ", reloc, "-", codeend - 1
      !warn "floppy data: ", codeend, "-", dataend - 1
      !warn "floppy dirbuf: ", dirbuf, "-", dirbuf + $1ff
      !if aligned_read = 0 {
        !warn "floppy encbuf: ", encbuf, "-", encbuf + $1ff
      } ;aligned_read
      !if allow_trees = 1 {
        !warn "floppy treebuf: ", treebuf, "-", treebuf + $1ff
      } ;allow_trees
      !warn "floppy driver start: ", unrelocdsk - init
    } ;verbose_info
  } ;enable_floppy
  !if reloc < $c000 {
    !if ((hdddataend + $ff) & -256) > $c000 {
      !serious "initial reloc too high, adjust to ", $c000 - (((hdddataend + $ff) & -256) - reloc)
    } ;hdddataend
    !if load_high = 1 {
      !if ((hdddataend + $ff) & -256) != $c000 {
        !warn "initial reloc too low, adjust to ", $c000 - (((hdddataend + $ff) & -256) - reloc)
      } ;hdddataend
      hdddirbuf = reloc - $200
      !if aligned_read = 0 {
        hddencbuf = hdddirbuf - $200
      } ;aligned_read
      !if allow_trees = 1 {
        !if fast_trees = 1 {
          !if ((aligned_read xor 1) + enable_write) > 0 {
            hddtreebuf = hddencbuf - $200
          } else { ;aligned_read = 1 and enable_write = 0
            hddtreebuf = hdddirbuf - $200
          } ;aligned_read = 0 or enable_write = 1
        } else { ;fast_trees = 0
          hddtreebuf = hdddirbuf
        } ;fast_trees
      } ;allow_trees
    } else { ;load_high = 0
      !pseudopc ((hdddataend + $ff) & -256) {
        hdddirbuf = *
        !if (hdddirbuf + $200) > $c000 {
          !if hdddirbuf < $d000 {
            !set hdddirbuf = reloc - $200
          } ;hdddirbuf
        } ;hdddirbuf
      }
      !if ((aligned_read xor 1) + rwts_mode) > 0 {
        !if fast_subindex = 0 {
          hddencbuf = hdddirbuf ;writes come from cache
        } else { ;fast_subindex = 1
          !if hdddirbuf < reloc {
            hddencbuf = hdddirbuf - $200
          } else { ;hdddirbuf
            hddencbuf = hdddirbuf + $200
            !if (hddencbuf + $200) > $c000 {
              !if hddencbuf < $d000 {
                !set hddencbuf = reloc - $200
              } ;hddencbuf
            } ;hddencbuf
          } ;hdddirbuf
        } ;fast_subindex
      } ;aligned_read = 0 or rwts_mode = 1
      !if allow_trees = 1 {
        !if fast_trees = 1 {
          !if ((aligned_read xor 1) + rwts_mode) > 0 {
            !if hddencbuf < reloc {
              hddtreebuf = hddencbuf - $200
            } else { ;hddencbuf
              hddtreebuf = hddencbuf + $200
              !if (hddtreebuf + $200) > $c000 {
                !if hddtreebuf < $d000 {
                  !set hddtreebuf = reloc - $200
                } ;hddtreebuf
              } ;hddtreebuf
            } ;hddencbuf
          } else { ;aligned_read = 1
            !if hdddirbuf < reloc {
              hddtreebuf = hdddirbuf - $200
            } else { ;hdddirbuf
              hddtreebuf = hdddirbuf + $200
              !if (hddtreebuf + $200) > $c000 {
                !if hddtreebuf < $d000 {
                  !set hddtreebuf = reloc - $200
                } ;hddtreebuf
              } ;hddtreebuf
            } ;hdddirbuf
          } ;aligned_read
        } else { ;fast_trees = 0
            hddtreebuf = hdddirbuf
        } ;fast_trees
      } ;allow_trees
    } ;load_high
  } else { ;reloc > $c000
    !if ((hdddataend + $ff) & -256) != 0 {
      !if ((hdddataend + $ff) & -256) < reloc {
        !serious "initial reloc too high, adjust to ", (0 - (((hdddataend + $ff) & -256) - reloc)) & $ffff
      } ;hdddataend
    } ;hdddataend
    !if load_high = 1 {
      !if enable_floppy = 0 {
        !if (((hdddataend + $ff) & -256) & $ffff) != 0 {
          !warn "initial reloc too low, adjust to ", (0 - (((hdddataend + $ff) & -256) - reloc)) & $ffff
        } ;hdddataend
      } ;enable_floppy
      hdddirbuf = reloc - $200
      !if aligned_read = 0 {
        hddencbuf = hdddirbuf - $200
      } ;aligned_read
      !if allow_trees = 1 {
        !if fast_trees = 1 {
          !if ((aligned_read xor 1) + enable_write) > 0 {
            hddtreebuf = hddencbuf - $200
          } else { ;aligned_read = 1 and enable_write = 0
            hddtreebuf = hdddirbuf - $200
          } ;aligned_read = 0 or enable_write = 1
        } else { ;fast_trees = 0
          hddtreebuf = hdddirbuf
        } ;fast_trees
      } ;allow_trees
    } else { ;load_high = 0
      !pseudopc ((hdddataend + $ff) & -256) {
        hdddirbuf = *
      }
      !if ((aligned_read xor 1) + rwts_mode) > 0 {
        !if fast_subindex = 0 {
          hddencbuf = hdddirbuf ;writes come from cache
        } else { ;fast_subindex = 1
          hddencbuf = hdddirbuf + $200
        } ;fast_subindex
      } ;aligned_read = 0 or rwts_mode = 1
      !if allow_trees = 1 {
        !if fast_trees = 1 {
          !if ((aligned_read xor 1) + enable_write) > 0 {
            hddtreebuf = hddencbuf + $200
          } else { ;aligned_read = 1 and enable_write = 0
            hddtreebuf = hdddirbuf + $200
          } ;aligned_read = 0 or enable_write = 1
        } else { ;fast_trees = 0
          hddtreebuf = hdddirbuf
        } ;fast_trees
      } ;allow_trees
    } ;load_high
  } ;reloc
  !if verbose_info = 1 {
    !warn "hdd code: ", reloc, "-", hddcodeend - 1
    !if hddcodeend != hdddataend {
      !warn "hdd data: ", hddcodeend, "-", hdddataend - 1
    }
    !warn "hdd dirbuf: ", hdddirbuf, "-", hdddirbuf + $1ff
    !if ((aligned_read xor 1) + rwts_mode) > 0 {
      !warn "hdd encbuf: ", hddencbuf, "-", hddencbuf + $1ff
    } ;aligned_read = 0 or rwts_mode = 1
    !if allow_trees = 1 {
      !warn "hdd treebuf: ", hddtreebuf, "-", hddtreebuf + $1ff
    } ;allow_trees
    !warn "hdd driver start: ", unrelochdd - init
    !if (one_page + enable_floppy) = 0 {
      !if ((hddcodeend - reloc) < $100) {
        !warn "one_page can be enabled, code is small enough"
      } ;hddcodeend
    } ;not one_page and not enable_floppy
  } ;verbose_info
} ;PASS2

readbuff
!byte $D3,$C1,$CE,$A0,$C9,$CE,$C3,$AE
