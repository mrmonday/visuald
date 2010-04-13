// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module hierarchy;

import std.c.windows.windows;
import std.c.windows.com;
import std.string;
import std.path;
import std.utf;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.fpstfmt;

//import vsshlids;
import comutil;
import logutil;
import trackprojectdocument;
import hierutil;
import chiernode;
import chiercontainer;
import propertypage;
import fileutil;
import dimagelist;
import config;

import dproject;
import dpackage;

///////////////////////////////////////////////////////////////////////////////
class CFileNode : CHierNode, 
		  ISpecifyPropertyPages,
		  IVsGetCfgProvider
{
	static const GUID iid = { 0x3fc35781, 0xfbb0, 0x42b6, [ 0xa2, 0x9b, 0x42, 0xdf, 0xa4, 0x96, 0x39, 0x2 ] };

	this(string filename)
	{
		mFilename = filename;
		SetName(getBaseName(filename));
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(CFileNode) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(ISpecifyPropertyPages) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsGetCfgProvider) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// ISpecifyPropertyPages
	override int GetPages( /* [out] */ CAUUID *pPages)
	{
		mixin(LogCallMix);
		return PropertyPageFactory.GetFilePages(pPages);
	}

	// IVsGetCfgProvider 
	override int GetCfgProvider(IVsCfgProvider* pCfgProvider)
	{
		if(Project prj = cast(Project) GetCVsHierarchy())
			return prj.GetCfgProvider(pCfgProvider);

		return E_NOINTERFACE;
	}

	// Property functions
	int GetProperty(VSHPROPID propid, out VARIANT var)
	{
		switch(propid)
		{
		case VSHPROPID_Name: 
		case VSHPROPID_SaveName: 
			var.vt = VT_BSTR;
			var.bstrVal = allocBSTR(GetName());
			return S_OK;
		default:
			return super.GetProperty(propid, var);
		}
		return E_NOTIMPL;
	}

	HRESULT GetGuidProperty(VSHPROPID propid, out GUID pGuid)
	{
		switch (propid)
		{
		case VSHPROPID_TypeGuid:
			// we represent physical file on disk so 
			// return the corresponding guid defined in vsshell.idl
			pGuid = GUID_ItemType_PhysicalFile;
			break;
		default:
			return DISP_E_MEMBERNOTFOUND;
		}
		return S_OK;
	}

	string GetFullPath()
	{
		if(isabs(mFilename))
			return mFilename;
		string root = GetRootNode().GetFullPath();
		root = getDirName(root);
		return root ~ "\\" ~ mFilename;
	}

	string GetFilename()
	{
		return mFilename;
	}

	string GetTool()
	{
		return mTool;
	}
	void SetTool(string tool)
	{
		mTool = tool;
	}

	string GetDependencies()
	{
		return mDependencies;
	}
	void SetDependencies(string dep)
	{
		mDependencies = dep;
	}

	string GetOutFile()
	{
		return mOutFile;
	}
	void SetOutFile(string file)
	{
		mOutFile = file;
	}

	string GetCustomCmd()
	{
		return mCustomCmd;
	}
	void SetCustomCmd(string cmd)
	{
		mCustomCmd = cmd;
	}
	
	bool GetLinkOutput()
	{
		return mLinkOut;
	}
	void SetLinkOutput(bool lnk)
	{
		mLinkOut = lnk;
	}

	int DoDefaultAction()
	{
		if(CVsHierarchy hier = GetCVsHierarchy())
			return hier.OpenDoc(this, false, false, true);
		return S_OK;
	}

	uint GetContextMenu() { return IDM_VS_CTXT_ITEMNODE; }

	override int QueryStatus( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ ULONG cCmds,
		/* [out][in][size_is] */ OLECMD* prgCmds,
		/* [unique][out][in] */ OLECMDTEXT *pCmdText)
	{
		OLECMD* Cmd = prgCmds;

		HRESULT hr = S_OK;
		bool fSupported = false;
		bool fEnabled = false;
		bool fInvisible = false;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			switch(Cmd.cmdID)
			{
			case cmdidOpenWith:
			case cmdidOpen:
				fSupported = true;
				fEnabled = true;
				break;
			default:
				hr = OLECMDERR.E_NOTSUPPORTED;
				break;
			}
		}
		else 
		{
			hr = OLECMDERR.E_NOTSUPPORTED;
		}
		if (SUCCEEDED(hr) && fSupported)
		{
			Cmd.cmdf = OLECMDF_SUPPORTED;
			if (fInvisible)
				Cmd.cmdf |= OLECMDF_INVISIBLE;
			else if (fEnabled)
				Cmd.cmdf |= OLECMDF_ENABLED;
		}

		if (hr == OLECMDERR.E_NOTSUPPORTED)
			hr = super.QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);

		return hr;
	}

	override int Exec( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ DWORD nCmdID,
		/* [in] */ DWORD nCmdexecopt,
		/* [unique][in] */ VARIANT *pvaIn,
		/* [unique][out][in] */ VARIANT *pvaOut)
	{
		int hr = OLECMDERR.E_NOTSUPPORTED;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			switch(nCmdID)
			{
			case cmdidOpenWith:
			case cmdidOpen:
				hr = GetCVsHierarchy().OpenDoc(this, false, nCmdID == cmdidOpenWith, true);
				break;
			default:
				break;
			}
		}

		if (hr == OLECMDERR.E_NOTSUPPORTED)
			hr = super.Exec(pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut);

		return hr;
	}

	HRESULT GetRDTDocumentInfo(
		/* [in]  */ string             pszDocumentName, 
		/* [out] */ IVsHierarchy*      ppIVsHierarchy      /* = NULL */, 
		/* [out] */ VSITEMID*          pitemid             /* = NULL */,
		/* [out] */ IVsPersistDocData* ppIVsPersistDocData /* = NULL */,
		/* [out] */ VSDOCCOOKIE*       pVsDocCookie        /* = NULL */)
	{
		// Get the document info.
		IVsRunningDocumentTable pRDT = queryService!(IVsRunningDocumentTable);
		if(!pRDT)
			return E_FAIL;
		scope(exit) release(pRDT);

		auto docname = _toUTF16z(pszDocumentName);
		IVsHierarchy srpIVsHierarchy;
		VSITEMID     vsItemId          = VSITEMID_NIL;
		IUnknown     srpIUnknown;
		VSDOCCOOKIE  vsDocCookie       = VSDOCCOOKIE_NIL;
		HRESULT hr = pRDT.FindAndLockDocument(
			/* [in]  VSRDTFLAGS dwRDTLockType   */ RDT_NoLock,
			/* [in]  LPCOLESTR pszMkDocument    */ docname,
			/* [out] IVsHierarchy **ppHier      */ &srpIVsHierarchy,
			/* [out] VSITEMID *pitemid          */ &vsItemId,
			/* [out] IUnknown **ppunkDocData    */ &srpIUnknown,
			/* [out] VSCOOKIE *pdwCookie        */ &vsDocCookie);

		// FindAndLockDocument returns S_FALSE if the doc is not in the RDT
		if (FAILED(hr))
			return hr;

		scope(exit) release(srpIUnknown);
		scope(exit) release(srpIVsHierarchy);

		// now return the requested info
		if (ppIVsHierarchy && srpIVsHierarchy)
			*ppIVsHierarchy = addref(srpIVsHierarchy);
		if (pitemid)
			*pitemid = vsItemId;
		if (ppIVsPersistDocData && srpIUnknown)
			srpIUnknown.QueryInterface(&IVsPersistDocData.iid, cast(void**)ppIVsPersistDocData);
		if (pVsDocCookie)
			*pVsDocCookie = vsDocCookie;

		return S_OK;
	}

	HRESULT GetDocInfo(
		/* [out, opt] */ bool*        pfOpen,     // true if the doc is opened
		/* [out, opt] */ bool*        pfDirty,    // true if the doc is dirty
		/* [out, opt] */ bool*        pfOpenByUs, // true if opened by our project
		/* [out, opt] */ VSDOCCOOKIE* pVsDocCookie)// VSDOCCOOKIE if open
	{
		if (!pfOpen && !pfDirty && !pfOpenByUs && !pVsDocCookie)
			return S_OK;

		if (pfOpen)       *pfOpen       = false;
		if (pfDirty)      *pfDirty      = false;
		if (pfOpenByUs)   *pfOpenByUs   = false;
		if (pVsDocCookie) *pVsDocCookie = VSDOCCOOKIE_NIL;

		HRESULT hr = S_OK;

		string strFullName = GetFullPath();

		IVsHierarchy srpIVsHierarchy;
		IVsPersistDocData srpIVsPersistDocData;
		VSITEMID vsitemid       = VSITEMID_NIL;
		VSDOCCOOKIE vsDocCookie = VSDOCCOOKIE_NIL;
		hr = GetRDTDocumentInfo(
			/* [in]  LPCTSTR             pszDocumentName    */ strFullName,
			/* [out] IVsHierarchy**      ppIVsHierarchy     */ &srpIVsHierarchy,
			/* [out] VSITEMID*           pitemid            */ &vsitemid,
			/* [out] IVsPersistDocData** ppIVsPersistDocData*/ &srpIVsPersistDocData,
			/* [out] VSDOCCOOKIE*        pVsDocCookie       */ &vsDocCookie);
		if (FAILED(hr))
			return hr;

		if (!srpIVsHierarchy || (vsDocCookie == VSDOCCOOKIE_NIL))
			return S_OK;

		if (pfOpen)
			*pfOpen = TRUE;
		if (pVsDocCookie)
			*pVsDocCookie = vsDocCookie;

		if (pfOpenByUs)
		{
			// check if the doc is opened by another project
			IVsHierarchy pMyHier = GetCVsHierarchy().GetIVsHierarchy();
			IUnknown punkMyHier;
			pMyHier.QueryInterface(&IID_IUnknown, cast(void **)&punkMyHier);
			IUnknown punkRDTHier;
			srpIVsHierarchy.QueryInterface(&IID_IUnknown, cast(void **)&punkRDTHier);
			if (punkRDTHier is punkMyHier)
				*pfOpenByUs = true;
			release(punkMyHier);
			release(punkRDTHier);
		}

		if (pfDirty && srpIVsPersistDocData)
		{
			BOOL dirty;
			hr = srpIVsPersistDocData.IsDocDataDirty(&dirty);
			*pfDirty = dirty != 0;
		}

		return S_OK;
	}

	HRESULT CloseDoc(/* [in] */ VSSLNCLOSEOPTIONS grfCloseOpts) 
	{
		HRESULT hr = S_OK;

		bool        fOpen       = false;
		bool        fOpenByUs   = false;
		VSDOCCOOKIE vsDocCookie = VSDOCCOOKIE_NIL;

		hr = GetDocInfo(
			/* [out, opt] BOOL*  pfOpen     */ &fOpen, // true if the doc is opened
			/* [out, opt] BOOL*  pfDirty    */ null, // true if the doc is dirty
			/* [out, opt] BOOL*  pfOpenByUs */ &fOpenByUs, // true if opened by our project
			/* [out, opt] VSDOCCOOKIE* pVsDocCookie*/ &vsDocCookie);// VSDOCCOOKIE if open
		if (FAILED(hr) || !fOpenByUs || vsDocCookie == VSDOCCOOKIE_NIL)
			return hr;

		IVsSolution pIVsSolution = queryService!(IVsSolution);
		if(!pIVsSolution)
			return E_FAIL;
		scope(exit) pIVsSolution.Release();

		// may return E_ABORT if prompt is cancelled
		return pIVsSolution.CloseSolutionElement(
			/* [in] VSSLNCLOSEOPTIONS grfCloseOpts */ grfCloseOpts, 
			/* [in] IVsHierarchy *pHier            */ null, 
			/* [in] VSCOOKIE docCookie             */ vsDocCookie);
	}

private:
	string mTool;
	string mDependencies;
	string mOutFile;
	string mCustomCmd;
	string mFilename; // relative or absolute
	bool mLinkOut;
}

// virtual folder
class CFolderNode : CHierContainer
{
	this(string name = "")
	{
		SetName(name);
	}

	// VSHPROPID_EditLabel
	override int GetEditLabel(BSTR *ppEditLabel)
	{
		*ppEditLabel = allocBSTR(GetName());
		return S_OK;
	}
	override int SetEditLabel(in BSTR pEditLabel)
	{
		SetName(to_string(pEditLabel));
		GetCVsHierarchy().OnPropertyChanged(this, VSHPROPID_Name, 0);
		return S_OK;
	}

	// Property functions
	override int GetProperty(VSHPROPID propid, out VARIANT var)
	{
		switch(propid)
		{
		case VSHPROPID_EditLabel: 
			return GetEditLabel(&var.bstrVal); // can fail
		default:
			return super.GetProperty(propid, var);
		}
		return E_NOTIMPL;
	}

	override int SetProperty(VSHPROPID propid, in VARIANT var)
	{
		switch(propid)
		{
		case VSHPROPID_EditLabel:
			if(var.vt != VT_BSTR)
				return returnError(E_INVALIDARG);
			return SetEditLabel(var.bstrVal); // can fail
		default:
			return super.SetProperty(propid, var);
		}
		return E_NOTIMPL;
	}

	override int QueryStatus( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ ULONG cCmds,
		/* [out][in][size_is] */ OLECMD* prgCmds,
		/* [unique][out][in] */ OLECMDTEXT *pCmdText)
	{
		OLECMD* Cmd = prgCmds;

		HRESULT hr = S_OK;
		bool fSupported = false;
		bool fEnabled = false;
		bool fInvisible = false;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			switch(Cmd.cmdID)
			{
			case cmdidAddNewItem:
			case cmdidAddExistingItem:
			case cmdidNewFolder:
				fSupported = true;
				fEnabled = true;
				break;
			case cmdidPaste:
				fSupported = true;
				fEnabled = false; // ClipboardHasDropFormat();
				break;
			default:
				hr = OLECMDERR.E_NOTSUPPORTED;
				break;
			}
		}
		else 
		{
			hr = OLECMDERR.E_NOTSUPPORTED;
		}
		if (SUCCEEDED(hr) && fSupported)
		{
			Cmd.cmdf = OLECMDF_SUPPORTED;
			if (fInvisible)
				Cmd.cmdf |= OLECMDF_INVISIBLE;
			else if (fEnabled)
				Cmd.cmdf |= OLECMDF_ENABLED;
		}

		if (hr == OLECMDERR.E_NOTSUPPORTED)
			hr = super.QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);

		return hr;
	}

	override int Exec( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ DWORD nCmdID,
		/* [in] */ DWORD nCmdexecopt,
		/* [unique][in] */ VARIANT *pvaIn,
		/* [unique][out][in] */ VARIANT *pvaOut)
	{
		int hr = OLECMDERR.E_NOTSUPPORTED;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			switch(nCmdID)
			{
			case cmdidAddNewItem:
			case cmdidAddExistingItem:
				hr = OnCmdAddItem(nCmdID == cmdidAddNewItem);
				break;

			case cmdidNewFolder:
				hr = OnCmdAddFolder();
				break;
			default:
				break;
			}
		}

		if (hr == OLECMDERR.E_NOTSUPPORTED)
			hr = super.Exec(pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut);

		return hr;
	}

	override HRESULT GetGuidProperty(VSHPROPID propid, out GUID pGuid)
	{
		switch (propid)
		{
		case VSHPROPID_TypeGuid:
			pGuid = GUID_ItemType_VirtualFolder;
			break;
		default:
			return DISP_E_MEMBERNOTFOUND;
		}
		return S_OK;
	}

	override uint GetContextMenu() { return IDM_VS_CTXT_FOLDERNODE; }

	//////////////////////////////////////////////////////////////////////
	HRESULT OnCmdAddFolder()
	{
		HRESULT hr = S_OK;

		// Get a reference to the project
		CProjectNode pProject = GetCVsHierarchy().GetProjectNode();

		// Create a new folder in the Project's folder
		CFolderNode pFolder = new CFolderNode;
		string strThisFolder = "Folder";
		pFolder.SetName(strThisFolder);

		Add(pFolder);

		//Fire an event to extensibility
		//CAutomationEvents::FireProjectItemsEvent(pFolder, CAutomationEvents::ProjectItemsEventsDispIDs::ItemAdded);

		// Since our expandable status may have changed, 
		// we need to refresh it in the UI
		GetCVsHierarchy().OnPropertyChanged(this, VSHPROPID_Expandable, 0);

		pProject.SetProjectFileDirty(true);
		return hr;
	}

	HRESULT OnCmdAddItem(bool fAddNewItem, wchar* pszSelectItem = null, wchar* pszExpandDir = null)
	{
		static string strFilter = "";      // filter string (initial/final value); valid if AllowStickyFilter set

		IVsAddProjectItemDlg srpAddItemDlg = queryService!(IVsAddProjectItemDlg);
		if(!srpAddItemDlg)
			return E_FAIL;

		VSADDITEMFLAGS dwFlags;
		if (fAddNewItem)
			dwFlags = VSADDITEM_AddNewItems | VSADDITEM_SuggestTemplateName | VSADDITEM_ShowLocationField;
		else
			dwFlags = VSADDITEM_AddExistingItems | VSADDITEM_AllowMultiSelect | VSADDITEM_AllowStickyFilter;

		string location = GetCVsHierarchy().GetProjectDir();
		BSTR bstrLocation = allocBSTR(location);

		// The AddProjectItemDlg function uses and can modify the value of the filter string, so here
		// we need to detach from the bstring and take the ownership of the one returned by the function.
		BSTR bstrFilters = allocBSTR(strFilter);

		HRESULT hr;
		hr = srpAddItemDlg.AddProjectItemDlg(GetCVsHierarchy().GetVsItemID(this), 
						     &g_projectFactoryCLSID, 
						     cast(IVsProject)GetCVsHierarchy(), dwFlags,
						     pszExpandDir, pszSelectItem,
						     &bstrLocation,
						     &bstrFilters,
						     null /*&fDontShowAgain*/);

		if(bstrFilters)
		{
			// Take the ownership of the returned string.
			strFilter = detachBSTR(bstrFilters);
		}
		detachBSTR(bstrLocation);

		release(srpAddItemDlg);
		// NOTE: AddItem() will be called via the hierarchy IVsProject to add items.
		return hr;
	}
}

class CProjectNode : CFolderNode
{
	this(string filename, CVsHierarchy hierarchy)
	{
		mFilename = filename;
		mHierarchy = hierarchy;
		mTrackProjectDocuments2Helper = new CVsTrackProjectDocuments2Helper(hierarchy);
	}
	~this()
	{
	}

	uint GetContextMenu() { return IDM_VS_CTXT_PROJNODE; }

	string GetFullPath()
	{
		return mFilename;
	}

	CVsHierarchy GetCVsHierarchy()
	{
		return mHierarchy;
	}

	bool QueryEditProjectFile()
	{
		return true;
	}

	void SetProjectFileDirty(bool dirty)
	{
		mDirty = dirty;
	}
	bool IsProjectFileDirty()
	{
		return mDirty;
	}

	CVsTrackProjectDocuments2Helper GetCVsTrackProjectDocuments2Helper()
	{
		return mTrackProjectDocuments2Helper;
	}
	void SetCVsTrackProjectDocuments2Helper(CVsTrackProjectDocuments2Helper helper)
	{
		mTrackProjectDocuments2Helper = helper;
	}

	override int QueryStatus( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ ULONG cCmds,
		/* [out][in][size_is] */ OLECMD* prgCmds,
		/* [unique][out][in] */ OLECMDTEXT *pCmdText)
	{
		OLECMD* Cmd = prgCmds;

		HRESULT hr = S_OK;
		bool fSupported = false;
		bool fEnabled = false;
		bool fInvisible = false;

		if(*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			switch(Cmd.cmdID)
			{
			case cmdidBuildSel:
			case cmdidRebuildSel:
			case cmdidCleanSel:
			case cmdidCancelBuild:

			case cmdidProjectSettings:
			case cmdidBuildSln:
			case cmdidUnloadProject:
			case cmdidSetStartupProject:
			case cmdidPropertiesWindow:
				fSupported = true;
				fEnabled = true;
				break;
			default:
				hr = OLECMDERR.E_NOTSUPPORTED;
				break;
			}
		}
		else if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K)
		{
			switch(Cmd.cmdID)
			{
			case cmdidBuildOnlyProject:
			case cmdidRebuildOnlyProject:
			case cmdidCleanOnlyProject:
				fSupported = true;
				fEnabled = true;
				break;
			default:
				hr = OLECMDERR.E_NOTSUPPORTED;
				break;
			}
		}
		else 
		{
			hr = OLECMDERR.E_NOTSUPPORTED;
		}
		if (SUCCEEDED(hr) && fSupported)
		{
			Cmd.cmdf = OLECMDF_SUPPORTED;
			if (fInvisible)
				Cmd.cmdf |= OLECMDF_INVISIBLE;
			else if (fEnabled)
				Cmd.cmdf |= OLECMDF_ENABLED;
		}

		if (hr == OLECMDERR.E_NOTSUPPORTED)
			hr = super.QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);

		return hr;
	}

	override int GetProperty(VSHPROPID propid, out VARIANT var)
	{
		if(propid == VSHPROPID_BrowseObject)
			return DISP_E_MEMBERNOTFOUND; // delegate to Project
		
		return super.GetProperty(propid, var);
	}

private:
	CVsTrackProjectDocuments2Helper mTrackProjectDocuments2Helper;
	CVsHierarchy mHierarchy;
	string mFilename; // always absolute
	bool mDirty;
}

///////////////////////////////////////////////////////////////////////////////
abstract class CVsHierarchy :	DisposingDispatchObject,
				IVsUIHierarchy,
				IVsPersistHierarchyItem
{
	void Dispose()
	{
		m_pParentHierarchy = release(m_pParentHierarchy);
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsHierarchy) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsUIHierarchy) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsPersistHierarchyItem) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// to be overridden
	HRESULT QueryStatusSelection(in GUID *pguidCmdGroup,
				     in ULONG cCmds, OLECMD *prgCmds, OLECMDTEXT *pCmdText,
				     ref CHierNode[] rgSelection, bool bIsHierCmd)
	{
		return returnError(OLECMDERR.E_NOTSUPPORTED);
	}

	// IVsUIHierarchy
	override int QueryStatusCommand( 
		/* [in] */ in VSITEMID itemid,
		/* [unique][in] */ GUID *pguidCmdGroup,
		/* [in] */ in ULONG cCmds,
		/* [size_is][out][in] */ OLECMD *prgCmds,
		/* [unique][out][in] */ OLECMDTEXT *pCmdText)
	{
version(none)
{
		mixin(LogCallMix);

		for(int i = 0; i < cCmds; i++)
			//logCall("  cmd%d = (id=%d, f=%d)", i, prgCmds[i].cmdID, prgCmds[i].cmdf);
			logCall("nCmdID = %s", cmd2string(*pguidCmdGroup, prgCmds[i].cmdID));
}

		if(CHierNode node = VSITEMID2Node(itemid))
		{
			CHierNode[] rgNodes;
			rgNodes ~= node;
			return QueryStatusSelection(pguidCmdGroup, cCmds, prgCmds, pCmdText, rgNodes, true);
		}

		return returnError(E_NOTIMPL);
	}
    
	override int ExecCommand( 
		/* [in] */ in VSITEMID itemid,
		/* [unique][in] */ GUID *pguidCmdGroup,
		/* [in] */ in DWORD nCmdID,
		/* [in] */ in DWORD nCmdexecopt,
		/* [unique][in] */ VARIANT *pvaIn,
		/* [unique][out][in] */ VARIANT *pvaOut)
	{
		mixin(LogCallMix);
		logCall("nCmdID = %s", cmd2string(*pguidCmdGroup, nCmdID));

		CHierNode node = VSITEMID2Node(itemid);
		CHierNode rgNodes[];
		GetSelectedNodes(rgNodes);

		if (!node)
			return OLECMDERR.E_NOTSUPPORTED;

		int hr = OLECMDERR.E_NOTSUPPORTED;
		if(*pguidCmdGroup == GUID_VsUIHierarchyWindowCmds)
		{
			switch(nCmdID)
			{
			case UIHWCMDID_RightClick:
				uint mnu = rgNodes.length > 1 ? GetContextMenu(rgNodes) : node.GetContextMenu();
				if (mnu != IDMX_NULLMENU)
					hr = ShowContextMenu(mnu, &guidSHLMainMenu, null);
				break;

			case UIHWCMDID_DoubleClick:
			case UIHWCMDID_EnterKey:
				hr = node.DoDefaultAction();
				break;
                
			case UIHWCMDID_StartLabelEdit:
				hr = node.OnStartLabelEdit();
				break;
                
			case UIHWCMDID_CommitLabelEdit:
				hr = node.OnCommitLabelEdit();
				break;
                
			case UIHWCMDID_CancelLabelEdit:
				hr = node.OnCancelLabelEdit();
				break;

			default:
				break;
			}
		}

		if(hr == OLECMDERR.E_NOTSUPPORTED && node)
			hr = node.Exec(pguidCmdGroup, nCmdID, nCmdexecopt, pvaIn, pvaOut);
		return hr;
	}
    
	// IVsHierarchy
	override int SetSite(IServiceProvider psp)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}
        
        override int GetSite(IServiceProvider *ppSP)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int QueryClose(BOOL *pfCanClose)
	{
		mixin(LogCallMix2);

		*pfCanClose = true;
		return S_OK;
	}

	override int Close()
	{
		mixin(LogCallMix);
		return S_OK;
	}

	int GetNodeIcon(CHierNode pNode)
	{
		if(CFileNode fnode = cast(CFileNode) pNode)
		{
			string tool = Config.GetCompileTool(fnode);
			switch(tool)
			{
			case "DMD":                 return kImageDSource;
			case kToolResourceCompiler: return kImageResource;
			case "Custom":              return kImageScript;
			default:                    return kImageDocument;
			}
		}
		if(pNode == m_pRootNode)
			return kImageProject;
		return kImageFolderClosed;
	}
	
	override int GetProperty(in VSITEMID itemid, in VSHPROPID propid, VARIANT* var)
	{
		//mixin(LogCallMix);
		CHierNode pNode = VSITEMID2Node(itemid);
		if(!pNode)
			return returnError(E_INVALIDARG);

		switch(propid)
		{
		case VSHPROPID_EditLabel:
			var.vt = VT_BSTR;
			return pNode.GetEditLabel(&var.bstrVal); // can fail
		case VSHPROPID_TypeName:
			var.vt = VT_BSTR;
			var.bstrVal = allocBSTR("typename");
			break;

		case VSHPROPID_ParentHierarchy:
			var.vt = VT_UNKNOWN;
			var.punkVal = addref(m_pParentHierarchy); // mProjectParent; // needs addref?
			break;
		case VSHPROPID_ParentHierarchyItemid:
			var.vt = VT_I4;
			var.lVal = m_dwParentHierarchyItemid;
			break;

		case VSHPROPID_Expandable:
			var.vt = VT_BOOL;
			var.boolVal = pNode.Expandable();
			break;
		case VSHPROPID_ExpandByDefault:
			var.vt = VT_BOOL;
			var.boolVal = pNode.ExpandByDefault();
			break;
		case VSHPROPID_IsHiddenItem:
			var.vt = VT_BOOL;
			var.boolVal = !pNode.IsDisplayable();
			break;
		case VSHPROPID_Container:
			var.vt = VT_BOOL;
			var.boolVal = pNode.IsContainer();
			break;
	
		case VSHPROPID_FirstVisibleChild:
			var.vt = VT_INT_PTR;
			var.lVal = GetFirstDisplayableNodeID(pNode);
			break;
		case VSHPROPID_FirstChild:
			var.vt = VT_INT_PTR;
			var.lVal = pNode.GetFirstMemberChildID();
			break;
		case VSHPROPID_NextVisibleSibling:
			var.vt = VT_INT_PTR;
			var.lVal = GetNextDisplayableNodeID(pNode);
			break;
		case VSHPROPID_NextSibling:
			var.vt = VT_INT_PTR;
			var.lVal = pNode.GetNextMemberSiblingID();
			break;
		case VSHPROPID_Parent:
			var.vt = VT_INT_PTR;
			var.lVal = GetVsItemID(pNode.GetParent());
			break;
		case VSHPROPID_Root:
			var.vt = VT_INT_PTR;
			var.lVal = VSITEMID_ROOT;
			break;
		case VSHPROPID_IconImgList:
			var.vt = VT_I4;
			var.lVal = cast(int) ImageList_LoadImageA(g_hInst, kImageBmp, 16, 10, CLR_DEFAULT,
								  IMAGE_BITMAP, LR_LOADTRANSPARENT);
			break;
		case VSHPROPID_IconHandle:
		case VSHPROPID_IconIndex:
			var.vt = VT_I4;
			var.lVal = GetNodeIcon(pNode);
			break;
		case VSHPROPID_OpenFolderIconIndex:
			var.vt = VT_I4;
			var.lVal = pNode == m_pRootNode ? kImageProject : kImageFolderOpened;
			break;
		case VSHPROPID_IsNonLocalStorage:
		case VSHPROPID_HandlesOwnReload:
		case VSHPROPID_CanBuildFromMemory:
			var.vt = VT_BOOL;
			var.boolVal = false;
			break;
		case VSHPROPID_DefaultEnableDeployProjectCfg:
		case VSHPROPID_DefaultEnableBuildProjectCfg:
			var.vt = VT_BOOL;
			var.boolVal = true;
			break;

	/+
		case VSHPROPID_ExtObject:
			var.vt = VT_DISPATCH;
			var.pdispVal = addref(mExtProject);
			break;
			//return DISP_E_MEMBERNOTFOUND; 
	+/

		case VSHPROPID_BrowseObject:
			//var.vt = VT_UNKNOWN;
			//var.punkVal = null;
			//break;
		case VSHPROPID_ProjectDir:
		    // ReloadableProjectFile, IsNonLocalStorage, CanBuildFromMemory, 
		    // DefaultEnableBuildProjectCfg, DefaultEnableDeployProjectCfg, 
		    // IsNonSearchable, HasEnumerationSideEffects, ExtObject
		    // 1001
		//case VSHPROPID2.EnableDataSourceWindow:
		//case VSHPROPID2.DebuggeeProcessId:
		case cast(VSHPROPID) 1001:
		default:
			if(pNode.GetProperty(propid, *var) == S_OK)
				break;

			//logCall("Getting unknown property %d for item %d!", propid, itemid);
			return DISP_E_MEMBERNOTFOUND;
			// return returnError(E_NOTIMPL); // DISP_E_MEMBERNOTFOUND; 
		}
		return S_OK;
	}

	override int SetProperty(in VSITEMID itemid, in VSHPROPID propid, in VARIANT var)
	{
		CHierNode pNode = VSITEMID2Node(itemid);
		if(!pNode)
			return returnError(E_INVALIDARG);

		if(pNode.SetProperty(propid, var) == S_OK)
			return S_OK;

		switch(propid)
		{
		case VSHPROPID_ParentHierarchy:
			if(var.vt != VT_UNKNOWN)
				return returnError(E_INVALIDARG);
			m_pParentHierarchy = release(m_pParentHierarchy);
			m_pParentHierarchy = addref(cast(IUnknown)var.punkVal);
			break;
		case VSHPROPID_ParentHierarchyItemid:
			if(var.vt != VT_I4)
				return returnError(E_INVALIDARG);
			m_dwParentHierarchyItemid = var.lVal;
			break;
		default:

			logCall("Setting unknown property %d for item %d!", propid, itemid);
			return DISP_E_MEMBERNOTFOUND;
		}
		return S_OK;
	}

	override int GetGuidProperty(in VSITEMID itemid, in VSHPROPID propid, GUID* pGuid)
	{
		if(CHierNode pNode = VSITEMID2Node(itemid))
			return pNode.GetGuidProperty(propid, *pGuid);
		return returnError(E_INVALIDARG);
	}

	override int GetNestedHierarchy(in VSITEMID itemid, in IID* iidHierarchyNested, void **ppHierarchyNested, VSITEMID* pitemidNested)
	{
		mixin(LogCallMix);

		if(CHierNode pNode = VSITEMID2Node(itemid))
			return pNode.GetNestedHierarchy(iidHierarchyNested, ppHierarchyNested, *pitemidNested);
		return returnError(E_FAIL);
	}

	override int GetCanonicalName(in VSITEMID itemid, BSTR *pbstrName)
	{
		logCall("GetCanonicalName(itemid=%s, pbstrMkDocument=%s)", _toLog(itemid), _toLog(pbstrName));

		if(CHierNode pNode = VSITEMID2Node(itemid))
		{
			*pbstrName = allocBSTR(pNode.GetCanonicalName());
			return S_OK;
		}
		return returnError(E_INVALIDARG);
	}

	override int ParseCanonicalName(in wchar* pszName, VSITEMID* pitemid)
	{
		mixin(LogCallMix2);

		string docName = tolower(to_string(pszName));
		CHierNode node = searchNode(GetRootNode(), delegate (CHierNode n) { return n.GetCanonicalName() == docName; });
		*pitemid = GetVsItemID(node);
		return node ? S_OK : E_FAIL;
	}

	override int Unused0()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AdviseHierarchyEvents(IVsHierarchyEvents pEventSink, uint *pdwCookie)
	{
		mixin(LogCallMix);

		mLastHierarchyEventSinkCookie++;
		mHierarchyEventSinks[mLastHierarchyEventSinkCookie] = addref(pEventSink);
		*pdwCookie = mLastHierarchyEventSinkCookie;

		return S_OK;
	}

	override int UnadviseHierarchyEvents(in uint dwCookie)
	{
//		mixin(LogCallMix);

		if(dwCookie in mHierarchyEventSinks)
		{
			release(mHierarchyEventSinks[dwCookie]);
			mHierarchyEventSinks.remove(dwCookie);
			return S_OK;
		}
		return returnError(E_INVALIDARG);
	}

	override int Unused1()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Unused2()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Unused3()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Unused4()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	// IVsPersistHierarchyItem
	override int IsItemDirty( 
		/* [in] */ in VSITEMID itemid,
		/* [in] */ IUnknown punkDocData,
		/* [out] */ BOOL *pfDirty)
	{
		scope auto srpPersistDocData = new ComPtr!(IVsPersistDocData)(punkDocData);
		if(!srpPersistDocData.ptr)
			return E_INVALIDARG;

		return srpPersistDocData.ptr.IsDocDataDirty(pfDirty);
	}

	override int SaveItem( 
		/* [in] */ in VSSAVEFLAGS dwSave,
		/* [in] */ in wchar* pszSilentSaveAsName,
		/* [in] */ in VSITEMID itemid,
		/* [in] */ IUnknown punkDocData,
		/* [out] */ BOOL* pfCanceled)
	{
		// validate itemid.
		if (itemid == VSITEMID_ROOT || itemid == VSITEMID_SELECTION || !VSITEMID2Node(itemid))
			return E_INVALIDARG;
    
		if (!punkDocData)
			return OLEERR.E_NOTRUNNING;    // we can only perform save if the document is open

		BSTR bstrMkDocumentNew;
		HRESULT hr = E_FAIL;

		if (VSSAVE_SilentSave & dwSave)
		{
			scope auto srpFileFormat = new ComPtr!(IPersistFileFormat)(punkDocData);
			scope auto pIVsUIShell = new ComPtr!(IVsUIShell)(queryService!(IVsUIShell));
			if(srpFileFormat.ptr && pIVsUIShell.ptr)
				hr = pIVsUIShell.ptr.SaveDocDataToFile(dwSave, srpFileFormat.ptr, pszSilentSaveAsName, &bstrMkDocumentNew, pfCanceled);
		}
		else
		{
			scope auto srpPersistDocData = new ComPtr!(IVsPersistDocData)(punkDocData);
			if(srpPersistDocData.ptr)
				hr = srpPersistDocData.ptr.SaveDocData(dwSave, &bstrMkDocumentNew, pfCanceled);
		}

		freeBSTR(bstrMkDocumentNew); // release string

		// if a SaveAs occurred we need to update to the fact our item's name has changed.
		// this includes the following:
		//      1. call RenameDocument on the RunningDocumentTable
		//      2. update the full path name for the item in our hierarchy
		//      3. a directory-based project may need to transfer the open editor to the
		//         MiscFiles project if the new file is saved outside of the project directory.
		//         This is accomplished by calling IVsExternalFilesManager::TransferDocument
		// This work can not be done by CVsHierarchy::SaveItem; this must be done in a 
		// derived subclass implementation of OnHandleSaveItemRename.
		//if ((!*pfCanceled) && bstrMkDocumentNew != NULL)
		//	hr = OnHandleSaveItemRename(itemid, punkDocData, bstrMkDocumentNew);

		return hr;
	}

	///////////////////////////////////////////////////////////////
	CHierNode VSITEMID2Node(VSITEMID itemid)
	{
		switch (itemid)
		{
		case VSITEMID_NIL:
			assert(false, "error: known invalid VSITEMID");
			return null;

		case VSITEMID_ROOT:
			return GetRootNode();

		case VSITEMID_SELECTION:
			assert(false, "error: Hierarchy illegaly called with VSITEMID_SELECTION");
			return null;

		default:
			if(CHierNode* pNode = itemid in gVsItemMap)
				return *pNode;
		}
		return null;
	}

	// Virtuals called in response to VSHPROPID_FirstChild, VSHPROPID_GextNextSibling. Defaults
	// just call pNode's GetFirstChild()/GetNext() methods. Override to display the nodes differently
	VSITEMID GetFirstDisplayableNodeID(CHierNode pNode)
	{
		return pNode.GetFirstChildID(true);
	}
	VSITEMID GetNextDisplayableNodeID(CHierNode pNode)
	{
		return GetVsItemID(pNode.GetNext());
	}

	// Following function returns the previous node in the hierwindow. It is obviously dependant on 
	// the sorting way GetFirstDisplayableNode, GetNextDisplayable node are implemented. 
	CHierNode GetPrevDisplayableNode(CHierNode pNode)
	{
		assert(pNode.IsDisplayable());
		return pNode.GetParent().GetPrevChildOf(pNode);
	}

public: // IVsHierarchyEvent propagation
	HRESULT OnItemAdded(CHierNode pNodeParent, CHierNode pNodePrev, CHierNode pNodeAdded)
	{
		assert(pNodeParent && pNodeAdded);
		VSITEMID itemidParent = GetVsItemID(pNodeParent);
		VSITEMID itemidSiblingPrev = GetVsItemID(pNodePrev);
		VSITEMID itemidAdded = GetVsItemID(pNodeAdded);

		foreach (advise; mHierarchyEventSinks)
			advise.OnItemAdded(itemidParent, itemidSiblingPrev, itemidAdded);
		return S_OK;
	}
	HRESULT OnItemDeleted(CHierNode pNode)
	{
		VSITEMID itemid = GetVsItemID(pNode);
		// Note that in some cases (deletion of project node for example), an Advise
		// may be removed while we are iterating over it. To get around this problem we
		// take a snapshot of the advise list and walk that.
		IVsHierarchyEvents[] sinks;

		foreach (advise; mHierarchyEventSinks)
			sinks ~= advise;

		foreach (advise; sinks)
			advise.OnItemDeleted(itemid);
		return S_OK;
	}
	HRESULT OnPropertyChanged(CHierNode pNode, VSHPROPID propid, DWORD flags)
	{
		VSITEMID itemid = GetVsItemID(pNode);
		if (pNode.IsDisplayable()) 
			foreach (advise; mHierarchyEventSinks)
				advise.OnPropertyChanged(itemid, propid, flags);
		return S_OK;
	}
	HRESULT OnInvalidateItems(CHierNode pNode)
	{
		VSITEMID itemid = GetVsItemID(pNode);

		foreach (advise; mHierarchyEventSinks)
			advise.OnInvalidateItems(itemid);
		return S_OK;
	}

	HRESULT OnInvalidateIcon(HICON hIcon)
	{
		foreach (advise; mHierarchyEventSinks)
			advise.OnInvalidateIcon(hIcon);
		return S_OK;
	}

	string GetProjectDir() { return getDirName(m_pRootNode.GetFullPath()); }
	CProjectNode GetProjectNode() { return m_pRootNode; }

	CHierContainer GetRootNode() { return m_pRootNode; }
	void SetRootNode(CProjectNode root) { m_pRootNode = root; }

	VSITEMID GetVsItemID(CHierNode node)
	{
		if(!node)
			return VSITEMID_NIL;
		if(node is GetRootNode())
			return VSITEMID_ROOT;
		return node.GetVsItemID();
	}

	IServiceProvider getServiceProvider()
	{
		return null;
	}

	IVsHierarchy GetIVsHierarchy()
	{
		return this;
	}

	//---------------------------------------------------------------------------
	// fill out an array of selected nodes
	//---------------------------------------------------------------------------
	HRESULT GetSelectedNodes(ref CHierNode rgNodes[])
	{
		IVsMonitorSelection srpMonSel = queryService!(IVsMonitorSelection);
		if(!srpMonSel)
			return returnError(E_FAIL);

		HRESULT hr = S_OK;
		VSITEMID itemid;                        // if VSITEMID_SELECTION then multiselection
		CHierNode pNode = null;
		IVsHierarchy srpIVsHierarchy;  // if NULL then selection spans VsHierarchies
		IVsMultiItemSelect srpIVsMultiItemSelect;
		ISelectionContainer srpISelectionContainer;        // unused?

		hr = srpMonSel.GetCurrentSelection(&srpIVsHierarchy, &itemid, &srpIVsMultiItemSelect, &srpISelectionContainer);
		if(hr == S_OK)
		{
			if (VSITEMID_NIL == itemid)
			{   // nothing selected
			}
			else if (VSITEMID_SELECTION != itemid)
			{	// Single selection. Note that callers of this function, may try to get the
				// selection when we aren't the active hierarchy - for this reason we need
				// to validate that the selected item belongs to us.
				if(srpIVsHierarchy is GetIVsHierarchy())
				{
					pNode = VSITEMID2Node(itemid);
					if (pNode)
						rgNodes ~= pNode;
					else
						logCall("  ERROR: invalid VSITEMID in selection");
				}
			}
			else if (srpIVsMultiItemSelect)
			{
				ULONG cItems = 0;
				BOOL  fSingleHierarchy = TRUE;
				hr = srpIVsMultiItemSelect.GetSelectionInfo(&cItems, &fSingleHierarchy);
				if (SUCCEEDED(hr))
				{
					assert(0 < cItems); // nothing selected should already be filtered out
					if(!fSingleHierarchy || srpIVsHierarchy is GetIVsHierarchy())
					{
						VSITEMSELECTION[] pItemSel = new VSITEMSELECTION[cItems];
						VSGSIFLAGS fFlags = fSingleHierarchy ? GSI_fOmitHierPtrs : cast(VSGSIFLAGS) 0;
						hr = srpIVsMultiItemSelect.GetSelectedItems(fFlags, cItems, pItemSel.ptr);
						if (SUCCEEDED(hr))
						{
							ULONG i;
							for (i = 0; i < cItems; ++i)
							{
								if (fSingleHierarchy || pItemSel[i].pHier is GetIVsHierarchy())
								{
									pNode = VSITEMID2Node(pItemSel[i].itemid);
									assert(pNode); // why is there an invalid itemid?
									if (pNode)
										rgNodes ~= pNode;
								}
							}
							if (!fSingleHierarchy)
							{   // release all the hierarchies
								for (i = 0; i < cItems; ++i)
									release(pItemSel[i].pHier);
							}
						}
					}
				}
			}
		}

		release(srpMonSel);
		release(srpIVsHierarchy);
		release(srpIVsMultiItemSelect);
		release(srpISelectionContainer);
		return hr;
	}

	uint GetContextMenu(CHierNode rgSelection[])
	{
		bool IsItemNodeCtx(uint idmx) 
		{
			return (idmx == IDM_VS_CTXT_ITEMNODE || idmx == IDM_VS_CTXT_XPROJ_MULTIITEM);
		}

		uint idmxMenu = IDMX_NULLMENU;
		bool fProjSelected = false;
		foreach(pNode; rgSelection)
		{
			uint idmxTemp = pNode.GetContextMenu();

			if(idmxTemp == IDMX_NULLMENU)
			{   // selection contains node that does not have a ctx menu
				idmxMenu = IDMX_NULLMENU;
				break;
			}
			else if(IDM_VS_CTXT_PROJNODE == idmxTemp)
			{
				// selection includes project node
				fProjSelected = TRUE;
			}
			else if (idmxMenu == IDMX_NULLMENU || idmxMenu == idmxTemp)
			{   // homogeneous selection
				idmxMenu = idmxTemp;
			}
			else if (IsItemNodeCtx(idmxTemp) && IsItemNodeCtx(idmxMenu))
			{
				// heterogeneous set of nodes that support common node commands
				idmxMenu = IDM_VS_CTXT_XPROJ_MULTIITEM;
			}
			else
			{   // heterogeneous set of nodes that have no common commands
				idmxMenu = IDMX_NULLMENU;
				break;
			}
		}

		// Multi-selection involving project node.
		if (idmxMenu != IDMX_NULLMENU && fProjSelected)
			idmxMenu = IDM_VS_CTXT_XPROJ_PROJITEM;

		return idmxMenu;
	}

	int ShowContextMenu(UINT iCntxtMenuID, in GUID* GroupGuid, IOleCommandTarget pIOleCmdTarg)
	{
		auto srpUIManager = queryService!(IVsUIShell);
		if(!srpUIManager)
			return E_FAIL;
		scope(exit) release(srpUIManager);

		POINT  pnt;
		GetCursorPos(&pnt);
		POINTS pnts = { cast(short)pnt.x, cast(short)pnt.y };

		int hr = srpUIManager.ShowContextMenu(0, GroupGuid, iCntxtMenuID, &pnts, pIOleCmdTarg);

		return hr;
	}

	void SetErrorInfo(HRESULT hr, string txt)
	{
		auto srpUIManager = queryService!(IVsUIShell);
		if(!srpUIManager)
			return;
		scope(exit) release(srpUIManager);

		auto wtxt = _toUTF16z(txt);
		wchar* wEmptyString = cast(wchar*) "\0"w.ptr;
		srpUIManager.SetErrorInfo(hr, wtxt, 0, wEmptyString, wEmptyString);
	}

	HRESULT OpenDoc(CFileNode pNode,
		/* [in]  */ bool             fNewFile            /*= FALSE*/,
		/* [in]  */ bool             fUseOpenWith        /*= FALSE*/,
		/* [in]  */ bool             fShow               /*= TRUE */,
		/* [in]  */ in GUID*         rguidLogicalView    = &LOGVIEWID_Primary,
		/* [in]  */ in GUID*         rguidEditorType     = &GUID_NULL, 
		/* [in]  */ in wchar*        pszPhysicalView     = null,
		/* [in]  */ IUnknown         punkDocDataExisting = DOCDATAEXISTING_UNKNOWN,
		/* [out] */ IVsWindowFrame*  ppWindowFrame       = null)
	{
		HRESULT hr = S_OK;

		// Get the IVsUIShellOpenDocument service so we can ask it to open a doc window
		IVsUIShellOpenDocument pIVsUIShellOpenDocument = queryService!(IVsUIShellOpenDocument);
		if(!pIVsUIShellOpenDocument)
			return returnError(E_FAIL);

		string strFullPath = pNode.GetFullPath();
		auto wstrFullPath = _toUTF16z(strFullPath);

		IVsWindowFrame srpIVsWindowFrame;
		if(!pszPhysicalView)
		{
			VSOSEFLAGS openFlags = OSE_ChooseBestStdEditor;

			if(fUseOpenWith)
				openFlags = OSE_UseOpenWithDialog;
			if(fNewFile)
				openFlags |= OSE_OpenAsNewFile;

			hr = pIVsUIShellOpenDocument.OpenStandardEditor(
				/* [in]  VSOSEFLAGS   grfOpenStandard           */ openFlags,
				/* [in]  LPCOLESTR    pszMkDocument             */ wstrFullPath,
				/* [in]  REFGUID      rguidLogicalView          */ rguidLogicalView,
				/* [in]  LPCOLESTR    pszOwnerCaption           */ _toUTF16z("%3"),
				/* [in]  IVsUIHierarchy  *pHier                 */ this,
				/* [in]  VSITEMID     itemid                    */ GetVsItemID(pNode),
				/* [in]  IUnknown    *punkDocDataExisting       */ punkDocDataExisting,
				/* [in]  IServiceProvider *pSP                  */ null,
				/* [out, retval] IVsWindowFrame **ppWindowFrame */ &srpIVsWindowFrame);
		}
		else
		{
			VSOSPEFLAGS openFlags = fNewFile ? OSPE_OpenAsNewFile : cast(VSOSPEFLAGS) 0;

			hr = pIVsUIShellOpenDocument.OpenSpecificEditor(
				/* VSOSPEFLAGS grfOpenSpecific      */ openFlags,
				/* LPCOLESTR pszMkDocument          */ wstrFullPath,
				/* REFGUID rguidEditorType          */ rguidEditorType,
				/* LPCOLESTR pszPhysicalView        */ cast(wchar*) pszPhysicalView,
				/* REFGUID rguidLogicalView         */ rguidLogicalView,
				/* LPCOLESTR pszOwnerCaption        */ _toUTF16z("%3"),
				/* IVsUIHierarchy *pHier            */ this,
				/* VSITEMID itemid                  */ pNode.GetVsItemID(),
				/* IUnknown *punkDocDataExisting    */ punkDocDataExisting,
				/* IServiceProvider *pSPHierContext */ null,
				/* IVsWindowFrame **ppWindowFrame   */ &srpIVsWindowFrame);
		}

		// Note that for external editors we don't get an srpIVsWindowFrame.
		if(SUCCEEDED(hr) && srpIVsWindowFrame)
		{
			if(fNewFile)
			{
				// SetUntitledDocPath is called by all projects after a new document instance is created.
				// Editors use the same CreateInstance/InitNew design pattern of standard COM objects.
				// Editors can use this method to perform one time initializations that are required after a new
				// document instance was created via IVsEditorFactory::CreateEditorInstance(CEF_CLONEFILE,...).
				// NOTE: Ideally this method would be called InitializeNewDocData but it is too late to rename this method.
				//              Most editors can ignore the parameter passed. It is a legacy of historical insignificance.
				VARIANT var;
				HRESULT hrTemp = srpIVsWindowFrame.GetProperty(VSFPROPID_DocData, &var);
				if(SUCCEEDED(hrTemp) && var.vt == VT_UNKNOWN && var.punkVal)
				{
					IVsPersistDocData srpDocData;
					hrTemp = var.punkVal.QueryInterface(&IVsPersistDocData.iid, cast(void**)&srpDocData);
					if(SUCCEEDED(hrTemp) && srpDocData)
					{
						srpDocData.SetUntitledDocPath(wstrFullPath);
						release(srpDocData);
					}
				}
			}

			// Show window
			if (fShow)
				srpIVsWindowFrame.Show();

			// Return window frame if requested
			if(ppWindowFrame)
				*ppWindowFrame = addref(srpIVsWindowFrame);
		}

		release(srpIVsWindowFrame);
		release(pIVsUIShellOpenDocument);

		return hr;
	}

	HRESULT AddItemSpecific(CHierContainer pNode,
		/* [in]                        */ VSADDITEMOPERATION    dwAddItemOperation,
		/* [in]                        */ in wchar*             pszItemName,
		/* [in]                        */ uint                  cFilesToOpen,
		/* [in, size_is(cFilesToOpen)] */ in wchar**            rgpszFilesToOpen,
		/* [in]                        */ HWND                  hwndDlg,
		/* [in]                        */ VSSPECIFICEDITORFLAGS grfEditorFlags,
		/* [in]                        */ in GUID*              rguidEditorType,
		/* [in]                        */ in wchar*             pszPhysicalView,
		/* [in]                        */ in GUID*              rguidLogicalView,
		/* [out, retval]               */ VSADDRESULT*          pResult)
	{ 
		*pResult = ADDRESULT_Failure;

		HRESULT hr     = S_OK;
		HRESULT hrTemp = S_OK;

		CProjectNode pProject = GetProjectNode();

		// CExecution singleEx(&GetExecutionCtx());

		// Return if the project file is not editable or the project file was reloaded
		if(!pProject.QueryEditProjectFile())
			return OLEERR.E_PROMPTSAVECANCELLED;

		switch(dwAddItemOperation)
		{
		case VSADDITEMOP_LINKTOFILE:
			// because we are a reference-based project system our handling for 
			// LINKTOFILE is the same as OPENFILE. 
			// a storage-based project system which handles OPENFILE by copying 
			// the file into the project directory would have distinct handling 
			// for LINKTOFILE vs. OPENFILE.
			// we fall through to VSADDITEMOP_OPENFILE....

		case VSADDITEMOP_OPENFILE:
		case VSADDITEMOP_CLONEFILE:
		{
			bool fNewFile = (dwAddItemOperation == VSADDITEMOP_CLONEFILE);

			for(uint i = 0; i < cFilesToOpen; i++)
			{
				CFileNode pNewNode;

				if (fNewFile)
				{
					assert(cFilesToOpen == 1);
					assert(rgpszFilesToOpen[i]);
					assert(pszItemName);

					pNewNode = AddNewFile(pNode, to_string(rgpszFilesToOpen[i]), to_string(pszItemName));
				}
				else
				{
					// create and add node for the existing file to the project
					pNewNode = AddExistingFile(pNode, to_string(rgpszFilesToOpen[i]));
				}
				if(!pNewNode)
				{
					// This means that we return an error code if even one 
					// of the Items failed to Add (in the add existing files case)
					hr = E_FAIL;
					continue;
				}

				// we are not opening an existing file if an editor is not specified
				if (!fNewFile && *rguidEditorType == GUID_NULL)
					continue;

				// open the item
				assert(grfEditorFlags & VSSPECIFICEDITOR_DoOpen);
				IVsWindowFrame srpWindowFrame;
				bool useView = (grfEditorFlags & VSSPECIFICEDITOR_UseView) != 0;

				// Standard open file
				hrTemp = OpenDoc(pNewNode, fNewFile /*fNewFile*/, 
							   false    /*fUseOpenWith*/,
							   true     /*fShow*/,
							   rguidLogicalView,
							   rguidEditorType,
							   useView ? null : pszPhysicalView,
							   null, 
							   &srpWindowFrame);
				
				if (FAILED(hrTemp))
				{
					// These don't affect the return value of this function because 
					// by this stage the file has been sucessfully added to the project.
					// But the problem can be reported to the user.
				}
			}
			break;
		}

		case VSADDITEMOP_RUNWIZARD: // Wizard was selected        
			return RunWizard(
				/* [in]  LPCOLESTR     pszItemName       */ pszItemName,
				/* [in]  ULONG         cFilesToOpen      */ cFilesToOpen,
				/* [in]  LPCOLESTR     rgpszFilesToOpen[]*/ rgpszFilesToOpen,
				/* [in]  HWND          hwndDlg           */ hwndDlg,
				/* [out] VSADDRESULT * pResult           */ pResult);
		
		default:
			*pResult = ADDRESULT_Failure;
			hr = E_INVALIDARG;
		}

		if (SUCCEEDED(hr))
			*pResult = ADDRESULT_Success;

/+
		if(GetExecutionCtx().IsCancelled() || hr == E_ABORT || hr == OLE_E_PROMPTSAVECANCELLED)
		{
			*pResult = ADDRESULT_Cancel;    
			hr = S_OK;
		}
+/

		return hr;
	}

	CFileNode AddNewFile(CHierContainer pNode, string strFullPathSource, string strNewFileName)
	{ 
		HRESULT hr = S_OK;

		if(!CheckFileName(strNewFileName))
		{
			SetErrorInfo(E_FAIL, format("The filename is not valid: %s", strNewFileName));
			return null;
		}

		if(!isabs(strNewFileName))
			strNewFileName = GetProjectDir() ~ "\\" ~ strNewFileName;

		// If target != source then we need to copy
		if (CompareFilenamesForSort(strFullPathSource, strNewFileName) != 0)
		{
			bool fCopied = true;
			bool bStatus = false;
			// Don't force an overwrite.
			if(std.file.exists(strNewFileName))
			{
				string msg = format("%s already exists. Overwrite?", strNewFileName);
				string caption = "Add new file";
				int msgRet = UtilMessageBox(msg, MB_YESNOCANCEL | MB_ICONEXCLAMATION, caption);

				if (msgRet != IDYES)
					return null;

				string docName = tolower(strNewFileName);
				CHierNode node = searchNode(GetRootNode(), delegate (CHierNode n) { return n.GetCanonicalName() == docName; });
				// Remove the corresponding node from the hierarchy, we will add a new one with the same name below
				if(node)
					hr = node.GetParent().Delete(node, this);
				assert(SUCCEEDED(hr));
			}

			try 
			{
				std.file.copy(strFullPathSource, strNewFileName);
			}
			catch(Exception)
			{
				// get windows error and produce error info
				return null;
			}

			// template was read-only, but our file should not be
			//if (fCopied)
			//	SetFileAttributes(strNewFileName, FILE_ATTRIBUTE_ARCHIVE);
		}

		// Now that we have made a copy of the template file, let's add our new file to the project
		return AddExistingFile(pNode, strNewFileName);
	}

	CFileNode AddExistingFile(CHierContainer pNode, string strFullPathSource, bool fSilent = false, bool fLoad = false)
	{
		// get the proper file name
		string strFullPath = strFullPathSource;

		if(!CheckFileName(strFullPath))
			return null;

		// check the file specified if we are not merely opening an existing project
		if (!fLoad)
		{
			if(!std.file.isfile(strFullPath))
			{
				if (!fSilent)
				{
					string msg = format("%s does not exist.", strFullPath);
					UtilMessageBox(msg, MB_OK, "Add file");
				}
				return null;
			}
			string canonicalName = tolower(strFullPath);
			CHierNode node = searchNode(GetRootNode(), delegate (CHierNode n) { return n.GetCanonicalName() == canonicalName; });
			if(node)
			{
				if (!fSilent)
				{
					string msg = format("%s is already in the project.", strFullPath);
					UtilMessageBox(msg, MB_OK, "Add file");
				}
				return null;
			}
		}

		// the file looks ok

		CProjectNode pProject = GetProjectNode();
		CVsTrackProjectDocuments2Helper pTrackDoc = pProject.GetCVsTrackProjectDocuments2Helper();

		if (!fSilent)
		{
			if(!pTrackDoc.CanAddItem(strFullPath))
				return null;
		}

		string projDir = GetProjectDir();
		string relPath = makeRelative(strFullPath, projDir);

		CFileNode pNewFile = new CFileNode(relPath);
		pNode.Add(pNewFile);

		if (!fSilent)
		{
			pTrackDoc.OnItemAdded(pNewFile);

			//Fire an event to extensibility
			//CAutomationEvents::FireProjectItemsEvent(pNewFile, CAutomationEvents::ProjectItemsEventsDispIDs::ItemAdded);
		}

		pProject.GetCVsHierarchy().OnPropertyChanged(pNode, VSHPROPID_Expandable, 0);
		pProject.SetProjectFileDirty(true);

		return pNewFile;
	}

	HRESULT RunWizard(
		/* [in]                        */ in wchar*       pszItemName,
		/* [in]                        */ ULONG           cFilesToOpen,
		/* [in, size_is(cFilesToOpen)] */ in wchar**      rgpszFilesToOpen,
		/* [in]                        */ HWND            hwndDlg,
		/* [out, retval]               */ VSADDRESULT*    pResult)
	{
		return E_NOTIMPL;
	}

private:
	CProjectNode m_pRootNode;

	// Hierarchy event advises
	IVsHierarchyEvents[uint] mHierarchyEventSinks;
	uint mLastHierarchyEventSinkCookie;

	BOOL   m_fHierClosed;

	// Properties to support being used as a nested hierarchy
	IUnknown m_pParentHierarchy;
	VSITEMID m_dwParentHierarchyItemid;

	// support VSHPROPID_OwnerKey
	wstring   m_bstrOwnerKey;

	static BOOL g_bStartedDrag;
	static BOOL g_bInContextMenu;   // is OK to support Cut/Copy,Paste/Rename/etc.

}
