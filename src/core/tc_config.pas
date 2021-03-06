{ TorChat - Get/Set client configuration settings

  Copyright (C) 2012 Bernd Kreuss <prof7bit@gmail.com>

  This source is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 3 of the License, or (at your option)
  any later version.

  This code is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web
  at <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing
  to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
  MA 02111-1307, USA.
}

unit tc_config;

{$mode objfpc}{$H+}

interface

uses
  {$ifdef windows}shlobj,{$endif} // for finding %APPDATA% etc.
  Classes,
  SysUtils,
  fpjson,
  tc_interface,
  tc_const;

type
  { TClientConfig }

  TClientConfig = class(TInterfacedObject, IClientConfig)
  strict private
    FProfileName: String;
    FPathTorExe: String;
    FConfigData: TJSONObject;
    procedure CreateDefaultConfig;
  public
    constructor Create(AProfileName: String);
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    procedure SetString(AKey: String; AValue: String; Encoded: Boolean = False);
    function GetString(AKey: String; Encoded: Boolean = False): String;
    function DataDir: String;
    function PathTorExe: String;
    function ListenPort: DWord;
    function TorHostName: String;
    function TorPort: DWord;
  end;

function DefaultPathTorExe: String;

implementation
uses
  tc_misc,
  base64,
  jsonparser;

{ TClientConfig }

constructor TClientConfig.Create(AProfileName: String);
begin
  FProfileName := AProfileName;
  FPathTorExe := DefaultPathTorExe;
  Load;
end;

destructor TClientConfig.Destroy;
begin
  WriteLn('TClientConfig.Destroy() ' + FProfileName);
  FConfigData.Free;
  inherited Destroy;
end;

procedure TClientConfig.Load;
var
  FS: TFileStream = nil;
  JParser: TJSONParser = nil;
  FileName: String;
begin
  WriteLn('TClientConfig.Load()');
  FileName := ConcatPaths([DataDir, 'config.json']);
  try
    FS := TFileStream.Create(FileName, fmOpenRead);
    JParser :=TJSONParser.Create(FS);
    FConfigData := JParser.Parse as TJSONObject;
  except
    on E: Exception do begin
      WriteLn('W TClientConfig.Load() could not load: ' + E.Message);
      if RenameFile(FileName, FileName + '.broken') then
        WriteLn('E renamed broken config file to ' + FileName + '.broken');
      CreateDefaultConfig;
    end;
  end;
  if assigned(FS) then FreeAndNil(FS);
  if assigned(JParser) then FreeAndNil(JParser);
end;

procedure TClientConfig.Save;
var
  Path: String;
  JData: String;
  FileName: String;
  TempName: StrinG;
  FS: TFileStream = nil;
  Success: Boolean;
begin
  WriteLn('TClientConfig.Save()');
  Success := False;
  Path := DataDir;
  TempName := ConcatPaths([Path,'_config.json']);
  FileName := ConcatPaths([Path,'config.json']);

  JData := FConfigData.FormatJSON([]);
  try
    FS := TFileStream.Create(TempName, fmCreate + fmOpenWrite);
    FS.Write(JData[1], Length(JData));
    Success := True;
  except
    on E: Exception do begin
      writeln('E TClientConfig.Save() could not save: ' + E.Message);
    end;
  end;
  if Assigned(FS) then FreeAndNil(FS);

  if Success then begin
    SafeDelete(FileName);
    RenameFile(TempName, FileName);
  end
  else
    SafeDelete(TempName);
end;

procedure TClientConfig.SetString(AKey: String; AValue: String; Encoded: Boolean);
begin
  WriteLn(_F('TClientConfig.SetString(''%s'')', [AKey]));
  if Encoded then
    AValue := EncodeStringBase64(AValue);
  try
    FConfigData.Strings[AKey] := AValue;
  except
    WriteLn(_F('TClientConfig.SetString(%s, %s) could not set value', [AKey, DebugFormatBinary(AValue)]));
  end;
end;

function TClientConfig.GetString(AKey: String; Encoded: Boolean): String;
begin
  WriteLn(_F('TClientConfig.GetString(''%s'')', [AKey]));
  try
    Result := FConfigData.Strings[AKey];
    if Encoded then
      Result := DecodeStringBase64(Result);
  except
    WriteLn('is empty');
    Result := '';
  end;
end;

function TClientConfig.DataDir: String;
var
  Success: Boolean;
  {$ifdef windows}
  AppDataPath: Array[0..MaxPathLen] of Char;
  {$endif}
begin
  {$ifdef windows}
    SHGetSpecialFolderPath(0, AppDataPath, CSIDL_APPDATA, false);
    Result := ConcatPaths([AppDataPath, 'torchat2']);
    //{$fatal Windows is not yet supported}
  {$else}
    Result := ExpandFileName('~/.torchat2');
  {$endif}

  if FProfileName <> '' then
    Result := Result + '_' + FProfileName;

  if not DirectoryExists(Result) then begin
    Success := False;
    if CreateDir(Result) then begin
      if CreateDir(ConcatPaths([Result, 'tor'])) then begin
        writeln('I created empty config directory ' + Result);
        Success := True;
      end;
    end;
    if not Success then
      writeln('E could not create config directory ' + Result);
  end;
end;

function TClientConfig.PathTorExe: String;
begin
  Result := FPathTorExe;
end;

function TClientConfig.ListenPort: DWord;
begin
  Result := 11009;
end;

function TClientConfig.TorHostName: String;
begin
  Result := '127.0.0.1';
end;

function TClientConfig.TorPort: DWord;
begin
  Result := 11109;
end;

function TryThesePaths(List: array of String): String;
begin
  For Result in List do begin
    WriteLn('Trying path: ', Result);
    if FileExists(Result) then begin
      WriteLn('found: ', Result);
      Exit;
    end;
  end;
  WriteLn('W none of the tested paths existed');
  Result := '';
end;


function DefaultPathTorExe: String;
{$ifdef windows}
var
  ProgramsPath: Array[0..MaxPathLen] of Char;
{$endif}
begin
  {$ifdef windows}
  SHGetSpecialFolderPath(0, ProgramsPath, CSIDL_PROGRAM_FILES, false);
  Result := TryThesePaths([
    ConcatPaths([ProgramsPath, 'Tor', 'tor.exe']),
    ConcatPaths([ProgramsPath, 'Vidalia Bundle', 'Tor', 'tor.exe']),
    ConcatPaths([ProgramsPath, 'Vidalia Relay Bundle', 'Tor', 'tor.exe'])
  ]);
  {$else}
  Result := TryThesePaths([
    '/usr/local/sbin/tor',
    '/usr/local/bin/tor',
    '/usr/sbin/tor',
    '/usr/bin/tor',
    '/sbin/tor',
    '/bin/tor'
  ]);
  {$endif}
end;

procedure TClientConfig.CreateDefaultConfig;
begin
  WriteLn('TClientConfig.CreateDefaultConfig()');
  FConfigData := TJSONObject.Create();
  Save;
end;

end.

