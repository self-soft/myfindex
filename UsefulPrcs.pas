{$MODE OBJFPC}{$H+}
unit UsefulPrcs;

interface

uses {$ifdef WINDOWS}Windows, {$else}{$endif}Sysutils, Mapchar, classes, FileUtil, LCLType, LCLProc,
  Process;
type CharSet = set of char;


const
  LabelForbiddenChars :
    CharSet=['?','*','<','>','|','"',':','\','/'];

const
  attrs : array[0..3] of integer = (faArchive, faHidden, SysUtils.faReadOnly, faSysFile);
  attrs_str = 'ahrs';

{$ifndef windows}
const
  DRIVE_UNKNOWN = 0;
  DRIVE_NO_ROOT_DIR = 1;
  DRIVE_REMOVABLE = 2;
  DRIVE_FIXED = 3;
  DRIVE_REMOTE = 4;
  DRIVE_CDROM = 5;
  DRIVE_RAMDISK = 6;
{$endif}

function killzeros(const s:string):string;
function Filter(s:string;Forbidden:CharSet):string;
function VolumeSN(Drive: string): string; { Seriennummer (HEX) }
function VolumeID(Drive: string): string; { Label oder Seriennummer, falls ungelabelt }
function GetFileSize(const FileName: string): Int64;
function SizeToStr(Size: Int64; fmt : ShortInt; explorerlike:Boolean): string;
function AttrToString(a: integer): string;
function SpecialDirectory(ID: integer): string;
function Decrypt(const S: string; Key: Word): string;
function Like(const AString, APattern: string): Boolean;
procedure EjectDrive(drive: string);
function UrlEncode(s: string): string;
function UrlEncodeQuote(s: string): string;
function UrlDecode(s: string): string;
procedure LevenshteinPQR(p, q, r: integer);
function LevenshteinDistance(const sString, sPattern: string): Integer;
function WordsLevenshteinDistance(const sString, sPattern: string): Integer;
function min(i,j:integer):integer;
function MyFormatStr(s:string;FStrFormat:integer):string;
function GetSpaceText(sl:TStrings): string;
procedure PCharToList(str:PChar;list:TStringList);
procedure CreateDirRecursiv(s:string);
{$ifndef windows}
function GetDriveType(mountpoint : string) : integer;
function getDeviceByMountpoint(mountpoint : string) : string;
{$endif}
function StripHotkey(TheCaption : string) : string;

implementation

procedure PCharToList(str:PChar;list:TStringList);
var
  s : string;
  idx : integer;
begin
  s := StrPas(str);
  idx := Pos(#13#10,s);
  while idx <> 0 do
  begin
    list.Add(Copy(s,1,idx-1));
    Delete(s,1,idx+1);
    idx := Pos(#13#10,s);
  end;
  list.Add(s);
end;

function killzeros(const s:string):string;
begin
  Result := s;
  while Pos(#0,Result) > 0 do
    Result[Pos(#0,Result)] := ' ';
end;

function GetSpaceText(sl:TStrings): string;
var
  u8string: String;
  u8char : char;
  needsQuotes : boolean;
  I, Count: Integer;
begin
  Count := sl.Count;
  if (Count = 1) and (sl[0] = '') then
    Result := '""'
  else
  begin
    Result := '';
    for I := 0 to Count - 1 do
    begin
      u8string := sl[I];
      needsQuotes := false;
      for u8char in [#0..' ','"',','] do
      begin
        if (Pos(u8char, u8string) > 0) then needsQuotes := true;
      end;
      u8String := AnsiQuotedStr(u8String, '"');
      Result := Result + u8String + ' ';
    end;
  end;
end;

function MyFormatStr(s:string;FStrFormat:integer):string;
begin
  case FStrFormat of
    0 : Result := StringReplace(s, #13#10, ' ', [rfReplaceAll]);
    1 : ;
    2 : ;
    3 : Result := StringReplace(ansi2xml(s), #13#10, '<br>', [rfReplaceAll]);
  end;
end;

function min(i,j:integer):integer;
begin
  if i<j then Result := i else Result := j;
end;

function Filter(s:string;Forbidden:CharSet):string;
var
  i : integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    if not (s[i] in Forbidden) then Result := Result + s[i];
  Result := Copy(Result,1,50);
end;

function UrlEncode(s: string): string;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    case s[i] of
      'A'..'Z', 'a'..'z', '0'..'9', '.': Result := Result + s[i];
      ' ': Result := Result + '+';
    else
      Result := Result + '%' + IntToHex(Ord(s[i]), 2);
    end;
end;

function UrlEncodeQuote(s: string): string;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    if s[i] in ['"', '+', '%', '[', ']', '=', #13, #10] then
      Result := Result + '%' + IntToHex(Ord(s[i]), 2)
    else
      Result := Result + s[i];
end;

function UrlDecode(s: string): string;
var
  i: integer;
begin
  Result := '';
  i := 0;
  while i < Length(s) do
  begin
    Inc(i);
    case s[i] of
      '+': Result := Result + ' ';
      '%': begin
          Result := Result + chr(StrToInt('$' + Copy(s, i + 1, 2)));
          Inc(i, 2);
        end;
    else Result := Result + s[i];
    end;
  end;
end;


const
  VWin32_DIOC_DOS_IoCtl = 1; // Interrupt 21h

// WICHTIG: Im Zusammenhang mit DeviceIoControl
// IMMER PACKED-Records verwenden !!!!

type
  TDevIoCtl_Reg = packed record
    Reg_EBX: DWord;
    Reg_EDX: DWord;
    Reg_ECX: DWord;
    Reg_EAX: DWord;
    Reg_EDI: DWord;
    Reg_ESI: DWord;
    Reg_Flags: DWord;
  end;

function IsWindowsNT: boolean;
begin
  {$ifdef windows}
  if (Win32MajorVersion = 4) then
     if (Win32MinorVersion = 0) OR (Win32MinorVersion = 10) OR (Win32MinorVersion= 90) then
     result := false
  else
      result := true;
  {$else}
  result := false;
  {$endif}
end; {IsWindowsNT}

{$ifdef windows}
procedure EjectDrive(drive: string);
var
  hDevice: integer;
  cb: DWORD;
  s: string;
const
  IOCTL_STORAGE_EJECT_MEDIA = $2D4808;
begin
  //if not IsWindowsNT then EjectDrive98(drive) else
  //begin
    s := '\\.\' + drive + ':';
    hDevice := FileCreate(pchar(s)); { *Converted from CreateFile* }

//    if (hDevice = 0) then Result := False;

    DeviceIoControl(hDevice,
      IOCTL_STORAGE_EJECT_MEDIA, nil, 0,
      nil, 0, cb, nil);

    FileClose(hDevice); { *Converted from CloseHandle* }
  //end;
end;
{$else}
procedure EjectDrive(drive: string);
var
   ejectProcess : TProcess;
begin
     ejectProcess := TProcess.Create(nil);
     ejectProcess.CommandLine := 'eject ' + drive;
     ejectProcess.Execute;
     ejectProcess.Free;
end;

{$endif}

{ Like prüft die Übereinstimmung eines Strings mit einem Muster.
  So liefert Like('Delphi', 'D*p?i') true.
  Der Vergleich berücksichtigt Klein- und Großschreibung.
  Ist das nicht gewünscht, muss statt dessen
  Like(AnsiUpperCase(AString), AnsiUpperCase(APattern)) benutzt werden: }

function Like(const AString, APattern: string): Boolean;
var
  StringPtr, PatternPtr: PChar;
  StringRes, PatternRes: PChar;
begin
  Result := false;
  StringPtr := PChar(AString);
  PatternPtr := PChar(APattern);
  StringRes := nil;
  PatternRes := nil;
  repeat
    repeat // ohne vorangegangenes "*"
      case PatternPtr^ of
        #0: begin
            Result := StringPtr^ = #0;
            if Result or (StringRes = nil) or (PatternRes = nil) then
              Exit;
            StringPtr := StringRes;
            PatternPtr := PatternRes;
            Break;
          end;
        '*': begin
            inc(PatternPtr);
            PatternRes := PatternPtr;
            Break;
          end;
        '?': begin
            if StringPtr^ = #0 then
              Exit;
            inc(StringPtr);
            inc(PatternPtr);
          end;
      else begin
          if StringPtr^ = #0 then
            Exit;
          if StringPtr^ <> PatternPtr^ then begin
            if (StringRes = nil) or (PatternRes = nil) then
              Exit;
            StringPtr := StringRes;
            PatternPtr := PatternRes;
            Break;
          end
          else begin
            inc(StringPtr);
            inc(PatternPtr);
          end;
        end;
      end;
    until false;
    repeat // mit vorangegangenem "*"
      case PatternPtr^ of
        #0: begin
            Result := true;
            Exit;
          end;
        '*': begin
            inc(PatternPtr);
            PatternRes := PatternPtr;
          end;
        '?': begin
            if StringPtr^ = #0 then
              Exit;
            inc(StringPtr);
            inc(PatternPtr);
          end;
      else
        begin
          repeat
            if StringPtr^ = #0 then
              Exit;
            if StringPtr^ = PatternPtr^ then
              Break;
            inc(StringPtr);
          until false;
          inc(StringPtr);
          StringRes := StringPtr;
          inc(PatternPtr);
          Break;
        end;
      end;
    until false;
  until false;
end; {Michael Winter}

function SpecialDirectory(ID: integer): string;
{$ifdef windows}
var pidl: PItemIDList;
  Path: PChar;
{$endif}
begin
  {$ifdef windows}
  if SUCCEEDED(SHGetSpecialFolderLocation(0, ID, pidl)) then begin
    Path := StrAlloc(max_path);
    SHGetPathFromIDList(pidl, Path);
    Result := string(Path);
    if Result[length(Result)] <> '\' then
      Result := Result + '\';
  end;
  {$else}
  Result := '';
  {$endif}
end; {SpecialDirectory}

function AttrToString(a: integer): string;
var
  i : integer;
begin
  Result := attrs_str;
  for i := 0 to 3 do
    if not bool(a and attrs[i]) then Result[i+1] := '-';
//  if (a or faArchive) <> a then Result[1] := '-';
//  if (a or faHidden) <> a then Result[2] := '-';
//  if (a or faReadOnly) <> a then Result[3] := '-';
//  if (a or faSysFile) <> a then Result[4] := '-';
end;

function SizeToStr(Size: Int64; fmt : ShortInt; explorerlike:boolean): string;
var
  z: Extended;
  s: string;
begin
  if abs(fmt) > 5 then raise Exception.Create('Ungültiges Dateigrößen Format');
  if (abs(fmt) = 1) or ((fmt = 0) and (Size < 1000)) then
  begin
    s := 'Byte';
    z := Size;
    if fmt < 0 then
      Result := Format('%.0n', [z * 1.0]) else
      Result := Format('%.0n %s', [z * 1.0, s]);
    Exit;
  end else
    if (abs(fmt) = 2) or ((fmt = 0) and (Size < 1000 * 1000)) then
    begin
      s := 'KB';
      z := Size / 1024;
    end else
      if (abs(fmt) = 3) or ((fmt = 0) and (Size < 1000 * 1000 * 1000)) then
      begin
        s := 'MB';
        z := Size / 1024 / 1024;
      end else
        if (abs(fmt) = 4) or ((fmt = 0) and (Size < 1000000000000)) then
        begin
          s := 'GB';
          z := Size / 1024 / 1024 / 1024;
        end else
        begin
          s := 'TB';
          z := Size / 1024 / 1024 / 1024 / 1024;
        end;
  if explorerlike then
  begin
    if z <> 0 then z := z+1;
    Result := Format('%.0n %s', [z,s]);
  end else
  begin
  if fmt < 0 then
    Result := Format('%f', [z]) else
    Result := Format('%f %s', [z, s]);
  end;
end;

function GetFileSize(const FileName: string): Int64;
var
  srecResult: TSearchRec;
  //FindData: TWin32FindData;
begin
  if FindFirstUTF8(FileName, faAnyFile, srecResult) = 0 then
  begin
    Result := srecResult.Size;
    FindCloseUTF8(srecResult);
  end
  else
  begin
    Result := -1;
  end;
end;

function VolumeSN(Drive: string): string;
{$ifdef windows}
var
  OldErrorMode: Integer;
  Sernum, Unused, VolFlags: DWORD;
  Buf: array[0..MAX_PATH] of Char;
begin
  OldErrorMode := SetErrorMode(SEM_FAILCRITICALERRORS);
  try
    if GetVolumeInformation(PChar(Drive + ':\'), Buf,
      sizeof(Buf), @Sernum, Unused, VolFlags,
      nil, 0) then
      Result := IntToHex(sernum, 8)
    else Result := '*';
  finally
    SetErrorMode(OldErrorMode);
  end;
end;
{$else}
var
  hdparmProc : TProcess;
  grepProc : TProcess;
  AStringList : TStringList;
  ReadSize,ReadCount : integer;
  Buffer : array[0..127] of char;
begin
  hdparmProc := TProcess.Create(nil);
  grepProc := TProcess.Create(nil);
  AStringList := TStringList.Create;
  hdparmProc.CommandLine := 'hdparm -I '+Drive; //+' | grep Serial';
  grepProc.CommandLine := 'grep Serial';

  hdparmProc.Execute;
  grepProc.Execute;

  while hdparmProc.Running or (hdparmProc.Output.NumBytesAvailable > 0) do
  begin
       if hdparmProc.Output.NumBytesAvailable > 0 then
       begin
            readSize := hdparmProc.Output.NumBytesAvailable;
            if readSize > SizeOf(Buffer) then
               ReadSize := sizeOf(Buffer);
            ReadCount := hdparmProc.Output.Read(Buffer[0], ReadSize);
            grepProc.Input.Write(Buffer[0], ReadCount);
       end;
  end;
  grepProc.CloseInput;

  While grepProc.Running do
        Sleep(1);

  AStringList.LoadFromStream(grepProc.Output);
  result := AStringList.Text;
  hdparmProc.Free;
  grepProc.Free;
  AStringList.Free;
end;
{$endif}


function VolumeID(Drive: string): string;
{$ifdef windows}
var
  OldErrorMode: Integer;
  Sernum, Unused, VolFlags: DWORD;
  Buf: array[0..MAX_PATH] of Char;
begin
  OldErrorMode := SetErrorMode(SEM_FAILCRITICALERRORS);
  try
    if GetVolumeInformation(PChar(Drive + ':\'), Buf,
      sizeof(Buf), @Sernum, Unused, VolFlags,
      nil, 0) then
    begin
      if buf = '' then Result := 'SN: ' + IntToHex(sernum, 8) else
        Result := Buf;
    end else Result := '*';
  finally
    SetErrorMode(OldErrorMode);
  end;
end;
{$else}
var
  mountProc : TProcess;
  grepProc : TProcess;
  AStringList : TStringList;
  ReadSize,ReadCount : integer;
  Buffer : array[0..255] of char;
  strLabel : string;
  i,j : integer;
begin
  mountProc := TProcess.Create(nil);
  grepProc := TProcess.Create(nil);
  AStringList := TStringList.Create;
  mountProc.CommandLine := 'mount -l';
  grepProc.CommandLine := 'grep'+QuotedStr(Drive);

  mountProc.Execute;
  grepProc.Execute;

  while mountProc.Running or (mountProc.Output.NumBytesAvailable > 0) do
  begin
       if mountProc.Output.NumBytesAvailable > 0 then
       begin
            readSize := mountProc.Output.NumBytesAvailable;
            if readSize > SizeOf(Buffer) then
               ReadSize := sizeOf(Buffer);
            ReadCount := mountProc.Output.Read(Buffer[0], ReadSize);
            grepProc.Input.Write(Buffer[0], ReadCount);
       end;
  end;
  grepProc.CloseInput;

  While grepProc.Running do
        Sleep(1);

  AStringList.LoadFromStream(grepProc.Output);
  if AStringList.Text <> '' then
  begin
       for i := 1 to length(AStringList.Text) do begin
           if AStringList.Text[i] = '[' then
           begin
                for j := i+1 to length(AStringList.Text)-1 do
                begin
                   strLabel := strLabel + AStringList.Text[j];
                end;
           end;
       end;
       result := strLabel;
  end
  else
  begin
    result := 'SN: ' + VolumeSN(Drive);
  end;
  mountProc.Free;
  grepProc.Free;
  AStringList.Free;
end;
{$endif}


var
  FiR0: integer;
  FiP0: integer;
  FiQ0: integer;

function MinL(X, Y, Z: Integer): Integer;
begin
  if (X < Y) then Result := X else Result := Y;
  if (Result > Z) then Result := Z;
end;

procedure LevenshteinPQR(p, q, r: integer);
begin
  FiP0 := p;
  FiQ0 := q;
  FiR0 := r;
end;

function WordsLevenshteinDistance(const sString, sPattern: string): Integer;
const
  sep = [' ', ',', '.'];
var
  w: string;
  i, MinDistance, Distance: integer;
begin
  MinDistance := maxInt;
  w := '';
  for i := 1 to Length(sString) do
  begin
    if (sString[i] in sep) then
    begin
      Distance := LevenshteinDistance(w, sPattern);
      if Distance < MinDistance then MinDistance := Distance;
      w := '';
    end else w := w + sString[i];
  end;
  Result := MinDistance;
end;

function LevenshteinDistance(const sString, sPattern: string): Integer;
const
  MAX_SIZE = 50;
var
  aiDistance: array[0..MAX_SIZE, 0..MAX_SIZE] of Integer;
  i, j, iStringLength, iPatternLength, iMaxI, iMaxJ: Integer;
  chChar: Char;
  iP, iQ, iR, iPP: Integer;
begin
  iStringLength := length(sString);
  if (iStringLength > MAX_SIZE) then iMaxI := MAX_SIZE else
    iMaxI := iStringLength;
  iPatternLength := length(sPattern);
  if (iPatternLength > MAX_SIZE) then iMaxJ := MAX_SIZE else
    iMaxJ := iPatternLength;

  aiDistance[0, 0] := 0;
  for i := 1 to iMaxI do aiDistance[i, 0] := aiDistance[i - 1, 0] + FiR0;

  for j := 1 to iMaxJ do begin
    chChar := sPattern[j];
    if ((chChar = '*') or (chChar = '?')) then iP := 0 else iP := FiP0;
    if (chChar = '*') then iQ := 0 else iQ := FiQ0;
    if (chChar = '*') then iR := 0 else iR := FiR0;

    aiDistance[0, j] := aiDistance[0, j - 1] + iQ;

    for i := 1 to iMaxI do begin
      if (sString[i] = sPattern[j]) then iPP := 0 else iPP := iP;
   {*** aiDistance[i,j] := Minimum of 3 values ***}
      aiDistance[i, j] := MinL(aiDistance[i - 1, j - 1] + iPP,
        aiDistance[i, j - 1] + iQ,
        aiDistance[i - 1, j] + iR);
    end;
  end;
  Result := aiDistance[iMaxI, iMaxJ];
end;

{$R-,Q-}
function Decrypt(const S: String; Key: Word): String;
var                               // Aus Borlands techinfo
  I: byte;                        // Angepasst: SetLength
const
C1 = 52845;
C2 = 22719;

begin
  SetLength(Result,Length(s));
  for I := 1 to Length(S) do
    begin
      Result[I] := char(byte(S[I]) xor (Key shr 8));
      Key := (byte(S[I]) + Key) * C1 + C2;
    end;
end;

procedure CreateDirRecursiv(s:string);
var
  d : string;
  i : integer;
begin
  d := '';
  if Copy(s,Length(s),1) <> PathDelim then s := s + PathDelim;
  for i := 1 to length(s) do
    begin
    d:=d+s[i];
    if s[i] = PathDelim then
      CreateDirUTF8(d);
    end;
end;

{$ifndef windows}
function GetDriveType(mountpoint : string) : integer;
var
  mountedInfoProc : TProcess;
  lsprocSL, deviceSL : TStringList;
  device, DEVTYPE, ID_BUS : string;
  i, block, driveType : integer;

begin
  // Windows GetDriveType replacement
  device := getDeviceByMountpoint(mountpoint);
  mountedInfoProc := TProcess.Create(nil);
  lsprocSL := TStringList.Create;
  deviceSL := TStringList.Create;
  mountedInfoProc.CommandLine := 'udevadm info --query=property --name='+device;
  mountedInfoProc.Options:=mountedInfoProc.Options + [poUsePipes];
  mountedInfoProc.Execute;
  lsprocSL.LoadFromStream(mountedInfoProc.Output);
  driveType:=0;
  if (lsprocSL.Count > 0) AND (mountpoint <> 'tmpfs') then
  begin
    for i:=0 to lsprocSL.Count-1 do
    begin
      if pos('DEVTYPE', lsprocSL[i]) > 0 then
        DEVTYPE := copy(lsprocSL[i], 9, length(lsprocSL[i])-8);
      if pos('ID_BUS', lsprocSL[i]) > 0 then
        ID_BUS := copy(lsprocSL[i], 8, length(lsprocSL[i])-7);
      if pos('ID_CDROM', lsprocSL[i]) > 0 then
        driveType:=5;
      if pos('SUBSYSTEM=net', lsprocSL[i]) > 0 then
        driveType:=4;
    end;
  end
  else
   if mountpoint='tmpfs' then
     driveType:=6;
  if driveType < 4 then
  begin
    if ID_BUS='usb' then
      driveType:=2;
    if ID_BUS='ata' then
      driveType:=3;
  end;
  result := driveType;
  mountedInfoProc.Free;
  lsprocSL.Free;
  deviceSL.Free;
end;

function getDeviceByMountpoint(mountpoint : string) : string;
var
  mountedInfoProc : TProcess;
  mountedSL : TStringList;
  i, j : integer;
begin
  mountedInfoProc := TProcess.Create(nil);
  mountedSL := TStringList.Create;
  mountedInfoProc.CommandLine := 'mount';
  mountedInfoProc.Options:=mountedInfoProc.Options + [poUsePipes];
  mountedInfoProc.Execute;
  mountedSL.LoadFromStream(mountedInfoProc.Output);
  if mountedSL.Count > 0 then
  begin
    for i := 0 to mountedSL.Count - 1 do
    begin
      if AnsiPos(' '+mountpoint+' ', mountedSL[i]) > 0 then
      begin
        j := 1;
        while mountedSL[i][j] <> ' ' do
        begin
          result := result + mountedSL[i][j];
          inc(j);
        end;
      end;
    end;
  end;
  mountedSL.Free;
  mountedInfoProc.Free;
end;
{$endif}

function StripHotkey(TheCaption : string) : string;
var
  i : integer;
begin
  if length(TheCaption) > 0 then
  begin
    if length(TheCaption) > 1 then
    begin
    if TheCaption[1] = '&' then
      for i := 2 to length(TheCaption) do
        result := result + TheCaption[i];
    end
    else
      if TheCaption = '&' then
        result := ''
      else
        result := TheCaption;
  end
  else
    result := '';
end;

initialization
  LevenshteinPQR(1, 1, 1);


end.
