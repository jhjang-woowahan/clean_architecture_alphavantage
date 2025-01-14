﻿unit alpha.adapter.serverService;

interface

uses
  alpha.portIn.serverUseCase, alpha.domain.serverEntities, alpha.portOut.traderUseCase, alpha.domain.traderEntities,

  m.httpService, m.objMngTh, wp.log, wp.Event,
  System.Generics.Collections, Spring.Collections,

  System.SysUtils, System.Classes;

type
  TDataModule = THttpServiceDataModule;
  TalphaAdapterServerService = class(TDataModule, IAlphaPortInServerUseCase, IAlphaPortOutTraderUseCase)
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
    FPortInEvent: TAlphaPortInServerEventClass;
    FPortOutEvent: TAlphaPortOutTraderEventClass;
    FInflationRsp: TAlphaBody;
    FCpiRsp: TAlphaBody;
    FYield10YRsp: TAlphaBody;
    FMngTh: TObjMngTh;
    function GetInflation: TAlphaBody;
    function GetCpi: TAlphaBody;
    function GetYield10Y: TAlphaBody;
    function GetEvent: TAlphaPortInServerEventClass;
    function GetPortOutEvent: TAlphaPortOutTraderEventClass;
  public
    procedure ReqInflation;
    procedure ReqCpi;
    procedure ReqYield10Y;

    procedure Save;
  end;

//var
//  alphaAdapterServerService: TalphaAdapterServerService;

implementation

{%CLASSGROUP 'Vcl.Controls.TControl'}

{$R *.dfm}

uses
  factory.DB,
  m.httpClient,

  Spring.Services, Spring.Container, Vcl.Forms, Aurelius.Engine.ObjectManager
  ;

{ TalphaAdapterServerController }

procedure TalphaAdapterServerService.DataModuleCreate(Sender: TObject);
begin
  Log := TwpLoggerFactory.CreateSingle(ClassName);

  FPortInEvent.OnSync := TEvent<TProc>.Create;
  FPortInEvent.OnInflation := TEvent<TProc>.Create;
  FPortInEvent.OnCpi := TEvent<TProc>.Create;
  FPortInEvent.OnYield10Y := TEvent<TProc>.Create;

  FPortOutEvent.OnSave := TEvent<TProc>.Create;

  FMngTh := TObjMngTh.Create(ClassName + '.MngTh', FactoryDB.CreateSingleMng(ClassName + '.ObjMng'));
  FMngTh.Start;
end;

procedure TalphaAdapterServerService.DataModuleDestroy(Sender: TObject);
begin
  FMngTh.Terminate;
  FMngTh := nil;

  if Assigned(FInflationRsp) then
    FreeAndNil(FInflationRsp);

  if Assigned(FCpiRsp) then
    FreeAndNil(FCpiRsp);

  if Assigned(FYield10YRsp) then
    FreeAndNil(FYield10YRsp);
end;

function TalphaAdapterServerService.GetCpi: TAlphaBody;
begin
  Result := FCpiRsp;
end;

function TalphaAdapterServerService.GetEvent: TAlphaPortInServerEventClass;
begin
  Result := FPortInEvent;
end;

function TalphaAdapterServerService.GetInflation: TAlphaBody;
begin
  Result := FInflationRsp;
end;

function TalphaAdapterServerService.GetPortOutEvent: TAlphaPortOutTraderEventClass;
begin
  Result := FPortOutEvent;
end;

function TalphaAdapterServerService.GetYield10Y: TAlphaBody;
begin
  Result := FYield10YRsp;
end;

procedure TalphaAdapterServerService.ReqCpi;
begin
  ASync(TAlphaCpiTask.Create(
    procedure(ATask: THttpClientTask)
    var
      LTask: TAlphaCpiTask absolute ATask;
    begin
      if not Log.IfSendWarning(LTask.HTTPSuccess, LTask.ClassName) then
        Log.SendError(LTask.HttpErMsg)
      else
      begin
        LTask.MoveTo(FCpiRsp);
        for var LProc in FPortInEvent.OnCpi.Listeners do
          if Assigned(LProc) then
            LProc();
      end;
    end));
end;

procedure TalphaAdapterServerService.ReqInflation;
begin
  ASync(TAlphaInflationTask.Create(
    procedure(ATask: THttpClientTask)
    var
      LTask: TAlphaInflationTask absolute ATask;
    begin
      if not Log.IfSendWarning(LTask.HTTPSuccess, LTask.ClassName) then
        Log.SendError(LTask.HttpErMsg)
      else
      begin
        LTask.MoveTo(FInflationRsp);
        for var LProc in FPortInEvent.OnInflation.Listeners do
          if Assigned(LProc) then
            LProc();
      end;
    end));
end;

procedure TalphaAdapterServerService.ReqYield10Y;
begin
  ASync(TAlphaYield10YTask.Create(
    procedure(ATask: THttpClientTask)
    var
      LTask: TAlphaYield10YTask absolute ATask;
    begin
      if not Log.IfSendWarning(LTask.HTTPSuccess, LTask.ClassName) then
        Log.SendError(LTask.HttpErMsg)
      else
      begin
        LTask.MoveTo(FYield10YRsp);
        for var LProc in FPortInEvent.OnYield10Y.Listeners do
          if Assigned(LProc) then
            LProc();
      end;
    end));
end;

procedure TalphaAdapterServerService.Save;
begin
  FMngTh.ASync(
    function(AMng: TObjectManager): TArray<Int64>
    begin
      var LBuf := TArray<TAlphaBody>.Create(FInflationRsp, FCpiRsp, FYield10YRsp);
      SetLength(Result, Length(LBuf));
      for var LAlphaBody in LBuf do
      begin
        var i := 0;
        var LTrans := AMng.Connection.BeginTransaction;
        try
          try
            var LIndicator := TIndicator.Create;
            try
              LIndicator.Name := LAlphaBody.Name;
              LIndicator.Interval := LAlphaBody.Interval;
              LIndicator.&Unit := LAlphaBody.&Unit;
              AMng.Save(LIndicator);
              for var LSrc in LAlphaBody.Datas do
              begin
                var LRaw := TRawData.Create;
                try
                  LRaw.IndicatorID := LIndicator.ID;
                  LRaw.Date := LSrc.Date;
                  LRaw.Value := LSrc.Value.ToDouble;
                  AMng.Save(LRaw);
                finally
                  if not AMng.IsAttached(LRaw) then
                    LRaw.Free;
                end;
              end;
              Result[i] := LIndicator.ID;
              Inc(i);
            finally
              if not AMng.IsAttached(LIndicator) then
                LIndicator.Free;
            end;
            AMng.Flush;
            SetLength(Result, i + 1);
          except on E: Exception do
            LTrans.Rollback;
          end;
        finally
          LTrans.Commit;
        end;
      end;
    end,
    procedure(AEntityIDs: TArray<Int64>)
    begin
      for var LProc in FPortOutEvent.OnSave.Listeners do
        if Assigned(LProc) then
          LProc();
    end)
end;

end.
