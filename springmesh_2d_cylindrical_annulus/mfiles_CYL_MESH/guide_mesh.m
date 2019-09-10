function GUIDE_MESH = guide_mesh(SETTINGS,GUIDE_MESH)
% Usage: GUIDE_MESH = guide_mesh(SETTINGS,GUIDE_MESH)
%
% Purpose:
%   Generation of a guide-mesh for a 2D cylindrical mesh using polar
%   coordinates (theta,r)
%
% Input:
%   SETTINGS   : [structure] : structure containing mesh settings
%   GUIDE_MESH : [structure] : structure containing guide mesh settings
%
% Output:
%   GUIDE_MESH : [structure] : structure containing guide mesh settings and
%                              the guide mesh itself in polar coordinates
%                              (theta,r)
% JMT May 2016
%
% Copyright (c) 2017, Jorge M. Taramon and Jason P. Morgan, RHUL
%--------------------------------------------------------------------------

%==========================================================================
% LOAD VARIABLES
%==========================================================================
deg2rad          = pi/180;
r_int            = SETTINGS.r_int;         % inner radius (km) of the spherical shell
r_ext            = SETTINGS.r_ext;         % outer radius (km) of the spherical shell
theta0           = GUIDE_MESH.theta0;      % colatitude (degrees) of the point around which the 
                                           % refined and transition zones are defined
l0_coarse        = GUIDE_MESH.l0_coarse;   % desired length (km) for coarse zone (constant)
l0_tran          = GUIDE_MESH.l0_coarse;   % desired length (km) for the boundary of transition zone
l0_ref           = GUIDE_MESH.l0_ref;      % desired length (km) for refined zone (constant)
% Transition Zone
w_tran           = GUIDE_MESH.w_tran;      % width of transition zone (km)
w_tran_deg       = w_tran/(deg2rad*r_ext); % width of transition zone in degrees
theta_tran_l     = theta0-w_tran_deg/2;    % colatitude of the left boundary in the transition zone
theta_tran_r     = theta0+w_tran_deg/2;    % colatitude of the right boundary in the transition zone
% Refined Zone
d_ref            = GUIDE_MESH.d_ref;       % max depth in the refined zone (km)
w_ref            = GUIDE_MESH.w_ref;       % width of refined zone (km)
w_ref_deg        = w_ref/(deg2rad*r_ext);  % width of refined zone in degrees
theta_ref_l      = theta0-w_ref_deg/2;     % colatitude of the left boundary in the refined zone
theta_ref_r      = theta0+w_ref_deg/2;     % colatitude of the right boundary in the refined zone

%==========================================================================
% GENERATE THE GUIDE-MESH
%==========================================================================
% Define points at a certain level (CMB) using the coordinates for transition and refined zones
theta1           = [0; theta_tran_l; theta_ref_l; theta_ref_r; theta_tran_r; 360];
r1               = repmat(r_int,size(theta1));
p_CMB_level      = [theta1 r1];

% Coarse zone
p_ref_level      = [p_CMB_level(:,1) (r_ext-d_ref)*ones(size(p_CMB_level,1),1)];
p_surf_level     = [p_CMB_level(:,1)       (r_ext)*ones(size(p_CMB_level,1),1)];
p_coarse         = [p_CMB_level; p_ref_level; p_surf_level];
p_coarse(p_coarse(:,1) >= theta_tran_l &...
         p_coarse(:,1) <= theta_tran_r,:) = []; % remove those nodes in transition and refined zones

% Transition zone 
p_CMB_level      = p_CMB_level(p_CMB_level(:,1) >= theta_tran_l & p_CMB_level(:,1) <= theta_tran_r,:);
p_ref_level      = [p_CMB_level(:,1) (r_ext-d_ref)*ones(size(p_CMB_level,1),1)];
p_surf_level     = [p_CMB_level(:,1)       (r_ext)*ones(size(p_CMB_level,1),1)];
p_tran           = [p_CMB_level; p_ref_level; p_surf_level];
p_tran(p_tran(:,1) >= theta_ref_l & p_tran(:,1) <= theta_ref_r & ...
       p_tran(:,2) >= r_ext-d_ref,:) = []; % remove those nodes in refined zone

% Refined zone 
p_CMB_level      = p_CMB_level(p_CMB_level(:,1) >= theta_ref_l & p_CMB_level(:,1) <= theta_ref_r,:);
p_ref_level      = [p_CMB_level(:,1) (r_ext-d_ref)*ones(size(p_CMB_level,1),1)];
p_surf_level     = [p_CMB_level(:,1)       (r_ext)*ones(size(p_CMB_level,1),1)];
p_ref       	 = [p_ref_level; p_surf_level];

% Create GCOORD_GUIDE and EL2NOD_GUIDE
GCOORD_GUIDE     = [p_coarse;p_tran;p_ref];              % guide mesh nodes in polar coordinates (theta,r)
[GCOORD_GUIDE,I] = unique(GCOORD_GUIDE,'rows','stable'); % remove repeated nodes
EL2NOD_GUIDE     = delaunay(GCOORD_GUIDE);               % create connectivity matrix

%==========================================================================
% SET THE DESIRED LENGTH (L0) FOR EVERY NODE OF THE GUIDE-MESH
%==========================================================================
L0_guide_coarse  = l0_coarse*ones(size(p_coarse,1),1); % desired bar length for the position of each node in the coarse zone
L0_guide_tran    = l0_tran*ones(size(p_tran,1),1);     % desired bar length for the position of each node in the transition zone
L0_guide_ref     = l0_ref*ones(size(p_ref,1),1);       % desired bar length for the position of each node in the refined zone
L0_guide         = [L0_guide_coarse; L0_guide_tran; L0_guide_ref];
L0_guide         = L0_guide(I); % take only the L0 values for the right number of nodes(after removing repeated nodes)

%==========================================================================
% CREATE OUTPUT STRUCTURE
%==========================================================================
GUIDE_MESH.GCOORD_GUIDE   = GCOORD_GUIDE;
GUIDE_MESH.EL2NOD_GUIDE   = EL2NOD_GUIDE;
GUIDE_MESH.L0_guide       = L0_guide;
GUIDE_MESH.p_coarse_guide = p_coarse;
GUIDE_MESH.p_tran_guide   = p_tran;
GUIDE_MESH.p_ref_guide    = p_ref;
GUIDE_MESH.r_int          = r_int;
GUIDE_MESH.r_ext          = r_ext;

%==========================================================================
% PLOTS
%==========================================================================
if SETTINGS.save_figs || SETTINGS.show_figs
    plot_guide_mesh(GUIDE_MESH,SETTINGS)
end
end % END OF FUNCTION guide_mesh