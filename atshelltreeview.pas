{*****************************************************
ATShellTreeview component
Copyright (c) 2020 Alexey Torgashin (UVviewsoft.com)
License: MPL 2.0 or LGPL
******************************************************}

unit ATShellTreeview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ComCtrls,
  ATShellBase,
  Dialogs;

type
  TATShellTreeviewClick = (
    astcNone,
    astcFileClick,
    astcFileDblClick,
    astcFolderFold,
    astcFolderUnfold
    );

type
  TATShellTreeviewItemClick = procedure(const AFileName: string; AKind: TATShellTreeviewClick) of object;

type
  { TATShellTreeview }

  TATShellTreeview = class(TTreeView)
  private
    FFolder: string;
    FOnShellItemClick: TATShellTreeviewItemClick;
    function GetNodeFilename(Node: TTreeNode; out AIsDir: boolean): string;
    procedure SetFolder(const AValue: string);
    procedure HandleClick(ADouble: boolean);
    procedure ReadDirToNode(const AFolder: string; ANode: TTreeNode);
    procedure ReadDirToList(const AFolder: string; AList: TStringList; out ACountHidden: integer);
    procedure TreeClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    function GetCurrentFilename: string;
    procedure SetCurrentFilename(const AValue: string);
  protected
    procedure Delete(Node: TTreeNode); override;
    function CanExpand(Node: TTreeNode): boolean; override;
  public
    procedure Refresh;
    constructor Create(AOwner: TComponent); override;
    function FocusNodeOfFilename(const AFilename: string): boolean;
    function FindNodeOfFilename(const AFilename: string): TTreeNode;
    property Folder: string read FFolder write SetFolder;
    property CurrentFilename: string read GetCurrentFilename write SetCurrentFilename;
  published
    property OnShellItemClick: TATShellTreeviewItemClick read FOnShellItemClick write FOnShellItemClick;
  end;

implementation

function SBeginsWith(const S, SubStr: string): boolean;
var
  i: integer;
begin
  Result:= false;
  if S='' then exit;
  if SubStr='' then exit;
  if Length(SubStr)>Length(S) then exit;
  for i:= 1 to Length(SubStr) do
    if S[i]<>SubStr[i] then exit;
  Result:= true;
end;

type
  TATShellNodeData = class
  public
    Path: string;
    IsDir: boolean;
    Expanded: boolean;
  end;

function PrettyDirName(const S: string): string;
begin
  if ATShellOptions.ShowFolderBrackets then
    Result:= '['+S+']'
  else
    Result:= S;
end;

function _CompareFilenames(L: TStringList; Index1, Index2: integer): integer;
var
  s1, s2, ext1, ext2: string;
  d1, d2: PtrInt;
  dot1, dot2: boolean;
begin
  //show dirs first
  d1:= PtrInt(L.Objects[Index1]);
  d2:= PtrInt(L.Objects[Index2]);
  if d1<>d2 then
    exit(d2-d1);

  s1:= L[Index1];
  s2:= L[Index2];

  if ATShellOptions.ShowDotNamesFirst then
  begin
    dot1:= s1[1]='.';
    dot2:= s2[1]='.';

    if dot1<>dot2 then
      exit(ord(dot2)-ord(dot1));

    //compare dot-names w/o extensions (like VSCode)
    if dot1 then
      exit(CompareText(s1, s2));
  end;

  ext1:= ExtractFileExt(s1);
  ext2:= ExtractFileExt(s2);

  Result:= CompareText(ext1, ext2);
  if Result=0 then
    Result:= CompareText(s1, s2);
end;


function TATShellTreeview.GetNodeFilename(Node: TTreeNode; out AIsDir: boolean): string;
var
  Data: TATShellNodeData;
begin
  AIsDir:= false;
  Result:= '';
  if Assigned(Node) then
    if Assigned(Node.Data) then
    begin
      Data:= TATShellNodeData(Node.Data);
      AIsDir:= Data.IsDir;
      Result:= Data.Path;
    end;
end;


procedure TATShellTreeview.HandleClick(ADouble: boolean);
var
  P: TPoint;
  Node: TTreeNode;
  Kind: TATShellTreeviewClick;
  fn: string;
  bDir: boolean;
begin
  P:= ScreenToClient(Mouse.CursorPos);
  Node:= GetNodeAt(P.X, P.Y);
  if Assigned(Node) then
  begin
    fn:= GetNodeFilename(Node, bDir);
    if fn='' then exit;
    if bDir then
    begin
      if ATShellOptions.FoldDirsByClick then
      begin
        if Node.Expanded then
        begin
          Node.Collapse(false);
          Kind:= astcFolderFold;
        end
        else
        begin
          Node.Expand(false);
          Kind:= astcFolderUnfold;
        end;
        if Assigned(FOnShellItemClick) then
          FOnShellItemClick(fn, Kind);
      end;
    end
    else
    begin
      if ADouble then
        Kind:= astcFileDblClick
      else
        Kind:= astcFileClick;
      if Assigned(FOnShellItemClick) then
        FOnShellItemClick(fn, Kind);
    end;
  end;
end;

procedure TATShellTreeview.Delete(Node: TTreeNode);
begin
  if Assigned(Node.Data) then
    TObject(Node.Data).Free;
  inherited;
end;

function TATShellTreeview.CanExpand(Node: TTreeNode): boolean;
var
  Data: TATShellNodeData;
begin
  Result:= true;
  Data:= TATShellNodeData(Node.Data);
  if Data=nil then exit;
  if Data.Expanded then exit;
  if not Data.IsDir then exit;

  Data.Expanded:= true;
  ReadDirToNode(Data.Path, Node);
  //ShowMessage('Fill tree: '+Data.Path);
end;

procedure TATShellTreeview.Refresh;
begin
  Folder:= Folder;
end;

procedure TATShellTreeview.ReadDirToList(const AFolder: string;
  AList: TStringList; out ACountHidden: integer);
const
  MaskAll = {$ifdef windows} '*.*' {$else} '*' {$endif};
var
  Rec: TSearchRec;
  bDir: boolean;
  S: string;
begin
  AList.Clear;
  ACountHidden:= 0;
  if FindFirst(AFolder+DirectorySeparator+MaskAll, faAnyFile, Rec)=0 then
  try
    repeat
      S:= Rec.Name;
      if (S='.') or (S='..') then Continue;
      if (S[1]='.') then
      begin
        Inc(ACountHidden);
        if not ATShellOptions.ShowDotNames then
          Continue;
      end;

      bDir:= (Rec.Attr and faDirectory)<>0;
      AList.AddObject(S, TObject(PtrInt(bDir)));
    until FindNext(Rec)<>0;
  finally
    FindClose(Rec);
  end;
end;

procedure TATShellTreeview.TreeClick(Sender: TObject);
begin
  //dont override "Click" method- clicking fold-arrow is not ok
  HandleClick(false);
end;

procedure TATShellTreeview.TreeDblClick(Sender: TObject);
begin
  //dont override "DblClick" method- clicking fold-arrow is not ok
  HandleClick(true);
end;

constructor TATShellTreeview.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  ShowRoot:= false;
  ShowLines:= false;
  ReadOnly:= true;
  RowSelect:= true;

  OnClick:= @TreeClick;
  OnDblClick:= @TreeDblClick;

  Images:= ATShellIcons.Images;
end;

procedure TATShellTreeview.SetFolder(const AValue: string);
var
  RootNode: TTreeNode;
  NIcon: integer;
begin
  FFolder:= AValue;

  Items.Clear;
  if FFolder='' then exit;
  if not DirectoryExists(FFolder) then exit;

  ATShellIcons.InitConfig;

  ShowRoot:= not ATShellOptions.ShowRootNode;

  if ATShellOptions.ShowRootNode then
  begin
    RootNode:= Items.Add(nil, PrettyDirName(ExtractFileName(FFolder)));
    if ATShellOptions.ShowIcons then
      NIcon:= ATShellIcons.ImageIndexDir
    else
      NIcon:= -1;
    RootNode.ImageIndex:= NIcon;
    RootNode.SelectedIndex:= NIcon;
  end
  else
    RootNode:= nil;

  ReadDirToNode(FFolder, RootNode);

  if Assigned(RootNode) then
    RootNode.Expand(false);
end;

procedure TATShellTreeview.ReadDirToNode(const AFolder: string; ANode: TTreeNode);
var
  Node: TTreeNode;
  List: TStringList;
  bDir: boolean;
  NodeData: TATShellNodeData;
  CountHidden, NIcon: integer;
  S: string;
  i: integer;
begin
  if Assigned(ANode) then
    ANode.DeleteChildren
  else
    Items.Clear;

  List:= TStringList.Create;
  try
    ReadDirToList(AFolder, List, CountHidden);

    if List.Count=0 then
    begin
      if ATShellOptions.ShowTextForEmpty then
      begin
        if CountHidden=0 then
          S:= ATShellOptions.TextEmpty
        else
          S:= Format(ATShellOptions.TextEmptyWithHidden, [CountHidden]);
        Node:= Items.AddChild(ANode, S);
      end;
      exit;
    end;

    List.CustomSort(@_CompareFilenames);

    for i:= 0 to List.Count-1 do
    begin
      S:= List[i];
      bDir:= List.Objects[i]<>nil;

      NodeData:= TATShellNodeData.Create;
      NodeData.Path:= AFolder+DirectorySeparator+S;
      NodeData.IsDir:= bDir;
      NodeData.Expanded:= false;

      if bDir then
        S:= PrettyDirName(S);

      Node:= Items.AddChildObject(ANode, S, NodeData);
      if not ATShellOptions.ShowIcons then
        NIcon:= -1
      else
      if NodeData.IsDir then
        NIcon:= ATShellIcons.ImageIndexDir
      else
        NIcon:= ATShellIcons.ImageIndex(NodeData.Path);
      Node.ImageIndex:= NIcon;
      Node.SelectedIndex:= NIcon;

      //add fictive child, to show expand arrow
      if bDir then
        Items.AddChild(Node, '?');
    end;
  finally
    FreeAndNil(List);
  end;
end;

function TATShellTreeview.FocusNodeOfFilename(const AFilename: string): boolean;
var
  Node: TTreeNode;
begin
  Node:= FindNodeOfFilename(AFilename);
  Result:= Assigned(Node);
  if Result then
  begin
    Select(Node);
    Node.MakeVisible;
  end;
end;

function TATShellTreeview.FindNodeOfFilename(const AFilename: string): TTreeNode;
var
  SParts, SPart, SCurDir, SFindText: string;
  Node: TTreeNode;
  N: integer;
  bFinal: boolean;
begin
  Result:= nil;
  if FFolder='' then exit;
  if not SBeginsWith(AFilename, FFolder+DirectorySeparator) then exit;

  SParts:= Copy(AFilename, Length(FFolder)+2, MaxInt);
  SCurDir:= FFolder;

  if ATShellOptions.ShowRootNode then
    Node:= Items[0]
  else
    Node:= nil;

  repeat
    N:= Pos(DirectorySeparator, SParts);
    bFinal:= N=0;
    if bFinal then
      N:= Length(SParts)+1;
    SPart:= Copy(SParts, 1, N-1);
    System.Delete(SParts, 1, N);
    SCurDir+= DirectorySeparator+SPart;

    if bFinal then
      SFindText:= SPart
    else
      SFindText:= PrettyDirName(SPart);

    if Node=nil then
      Node:= Items.FindTopLvlNode(SFindText)
    else
      Node:= Node.FindNode(SFindText);
    if Node=nil then exit;

    if bFinal then
      exit(Node);
    Node.Expand(false);
  until SParts='';
end;

procedure TATShellTreeview.SetCurrentFilename(const AValue: string);
begin
  FocusNodeOfFilename(AValue);
end;

function TATShellTreeview.GetCurrentFilename: string;
var
  Node: TTreeNode;
  bDir: boolean;
begin
  Result:= '';
  Node:= Selected;
  if Assigned(Node) then
    Result:= GetNodeFilename(Node, bDir);
end;


end.
