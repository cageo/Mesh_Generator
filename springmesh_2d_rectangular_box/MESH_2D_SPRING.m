function MESH_2D_SPRING
% MESH_2D_SPRING - 2D FINITE ELEMENT RECTANGULAR MESH GENERATOR
% 
% Code developed by Jorge M. Taramon & Jason P. Morgan, 2014-2015
% Based on 2D Cartesian version of Chao Shi
% Email contact: Jorge.TaramonGomez.2014@live.rhul.ac.uk
%
% Basic idea:
%   -- A MATLAB based 2D unstructured triangular rectangular mesh generator
%   -- Treat each side of the triangles as a spring (also called 'bars' in 
%      the code), and give different bars different desired length (L0), 
%      therefore by solving for the steady state of the spring (truss)
%      system, we arrive at an acceptable unstructured triangular mesh.
%
% Flow Chart:
%
%   1)Define refinement in mesh_parameters.m 
%     In case we want a coarse mesh with an embedded high resolution
%     region, create a guide-mesh that will be used to compute the desired
%     length (L0) of the springs at any point of the FE mesh by
%     interpolation.
%     -> L0 will be variable depending on the mesh region
%        (Coarse, Transition, Refined)
%     -> The guide-mesh is defined in Cartesian coordinates.
%     If we want a regular mesh we just need the h0 parameter (constant 
%     distance between 2 nodes).
%   2)Create a 1st guess for the nodes of the mesh.
%     -> Boundary nodes (fixed nodes and semi-free boundary nodes)
%        -> Nodes at the corners of the rectangular mesh are fixed.
%        -> The number of bnd nodes on each boundary is calculated using L0
%           given by the guide-mesh or the constant h0 for a regular mesh.
%     -> Interior nodes (better less than more) using circle packing
%        lattice with either L0 or h0.
%   3)Calculate for steady state of the spring system.
%     -> Finite Element approach: stiffness matrix, solve for new (x,y)
%     -> Boundary nodes are fixed on the boundary segments (can only move
%        along the segment).
%     -> A set of 3 cross bars is added (optional) to avoid over squashing
%     -> Balloon forces (optional) to help creating better triangles
%   4)Add and/or reject interior and/or boundary nodes.
%   5)Repeat 3) and 4) until the right nodal density is reached.
%   6)Apply local improvements in order to get higher quality triangles
%     (smooth interior nodes).
%   7)Repeat 3) and 6) until no more adjustment is needed and the quality
%     of the mesh is good.
%
% More details:
%
%   1)The logic is easy to understand with the 'spring system' model.
%     This code is inspired by the 'distmesh' paper (see ref.), and this
%     algorithm is ready to expand to 3-D (actually n-D).
%   2)One important subroutine 'daulanayn.m' is a built-in matlab function
%     and it is used to generate the triangulation.
%   3)A blocking techique (mentioned in Milamin paper) is applied during
%     the formation of stiffness matrix: trying to use only high speed
%     cache to finish the formation, while generating big enough blocks of
%     jobs to minimize the number of operations (BLAS).
%   4)In order to run this code for the first time, follow the next steps: 
%       1. Download "Suitsparse" from:
%          http://faculty.cse.tamu.edu/davis/SuiteSparse/SuiteSparse-4.0.2.tar.gz
%       2. Install it running SuiteSparse_install.m
%       3. Download mutils-0.4-2 from:
%          https://sourceforge.net/projects/milamin/files/mutils-0.4-2.zip
%       4. Install it running install.m (follow the instructions that will
%          appear in the Command Window)
%       5. In order to set the OUTPUT folder in your computer:
%          5.1. Write pctconfig in the Command Window
%          5.2. Open data_storage_2d.m
%          5.3. Create a new case for your computer:
%               - Introduce in case the hostname you obtained in 5.1, e.g.,
%                 case 'fpdc462' 
%               - Introduce in path2data the path you want to save the
%                 output data, e.g., path2data = '/Users/Tests/';
%
% References:
%
%    Persson, P.-O. and G. Strang, A Simple Mesh Generator in MATLAB.
%       SIAM Review, Vol. 46 (2), pp. 329-345, June 2004
%    M. Dabrowski et al., MILAMIN: MATLAB-based finite element method
%       solver for large problems, Geochem. Geophys. Geosyst., VOL. 9,
%       Q04030, 2008 
%    D. V. Hutton, Fundamentals of Finite Element Analysis, 4th Intl. ed.,
%       2004 
%    Zienkiewicz, O. C., and R. L. Taylor, The Finite Element Method, 5th
%       ed., 2000 
%
%
% TO DO: Make it compatible with Uzawa (Penalty)
%
% JMT Jun 2017
% JMT Oct 2017 : cleaned up 
%
% Copyright (c) 2017, Jorge M. Taramon and Jason P. Morgan, RHUL
%--------------------------------------------------------------------------

clock0 = clock; % initialize timing for profiling

fprintf(1,'\n\n\n\n');
fprintf(1,'========================================================\n');
fprintf(1,'          NEW CALCULATION USING MESH_2D_SPRING\n');
fprintf(1,'========================================================\n');
addpath([pwd '/mfiles_MESH']); % MESH_2D_SPRING core functions
addpath([pwd '/SETUP_TEST']);  % mesh parameters, meshes to load
addpaths_mutils(); % add path to MUTILS installation on current computer

%==========================================================================
% DEFINING MESH PARAMETERS
%==========================================================================
[SETTINGS,GUIDE_MESH] = mesh_parameters();

%==========================================================================
% CREATE OUTPUT FOLDER
%==========================================================================
SETTINGS = create_output_folder(SETTINGS);

%==========================================================================
% INITIALIZE GUIDE MESH
%==========================================================================
if strcmp(SETTINGS.refinement,'guide_mesh')
    switch SETTINGS.guide_mesh
        case 'new'
            GUIDE_MESH = guide_mesh(SETTINGS,GUIDE_MESH);
        case 'load'
            GUIDE_MESH = load_guide_mesh(SETTINGS);
    end
end

%==========================================================================
% INITIALIZE FIRST GUESS MESH
%==========================================================================
switch SETTINGS.first_guess
    case 'new'
        MESH = first_guess(SETTINGS,GUIDE_MESH);
    case 'load'
        MESH = load_first_guess(SETTINGS);
    otherwise
        error('typo in SETTINGS.first_guess')
end

%==========================================================================
% SET MESH PARAMETERS TO ENTER IN THE MAIN LOOP
%==========================================================================
MESH.worst_q = SETTINGS.q_tol - 0.0001;
MESH.mean_q  = SETTINGS.mean_q_tol - 0.0001;
MESH.iter    = 1;

%==========================================================================
% SAVE INITIAL MESH, GUIDE MESH AND CONFIGURATION
%==========================================================================
save([SETTINGS.outdir '/FIRST_GUESS_MESH'],'MESH');
save([SETTINGS.outdir '/GUIDE_MESH'],'GUIDE_MESH');
save([SETTINGS.outdir '/SETTINGS'],'SETTINGS');

%==========================================================================
% ITERATION LOOP
%==========================================================================
% Keep iterating until 1 of these 2 situations is reached:
% 1. Iterations (iter) reach the maximum number of iterations (itmax)
% 2. Worst quality factor (worst_q) reaches the tolerance for the quality
%    factor (q_tol), AND average of quality factor (mean_q) reaches the
%    tolerance for the average of quality factor (mean_q_tol)
while(MESH.iter <= SETTINGS.itmax &&...
     (MESH.worst_q < SETTINGS.q_tol || MESH.mean_q < SETTINGS.mean_q_tol))
   
    %======================================================================
    % DISPLAY ITERATION AND RUNTIME
    %======================================================================
    display_progress(MESH.iter,clock0)
    
    %======================================================================
    % SOLVE FOR NODAL POSITIONS
    %======================================================================
    MESH = solve_nodal_position(MESH,GUIDE_MESH,SETTINGS);
    
    if MESH.mean_misfit_bar_length >= SETTINGS.mean_misfit_bar_length_tol
        %==================================================================
        % ADD/REJECT NODES UNTIL THE DESIRED NODAL DENSITY IS ACHIEVED
        %==================================================================
        if abs(rms(MESH.rho)-rms(MESH.rho0))/rms(MESH.rho) > 0.4
            %==============================================================
            % ADD/REJECT NODES WHEN DESIRED NODAL DENSITY AND ACTUAL NODAL 
            % DENSITY ARE VERY DIFFERENT 
            % -> effective way to add/reject large number of nodes.
            %    This is useful when the inital mesh is coarse.
            %==============================================================
            MESH.add_reject_counter = 1; % to initialize
            
            while abs(rms(MESH.rho)-rms(MESH.rho0))/rms(MESH.rho) > 0.40

                MESH = add_reject_nodes(MESH,GUIDE_MESH,SETTINGS);
                
                MESH.rho0 = sqrt(2)./(MESH.L0.^2); % desired nodal desnsity
                MESH.rho  = sqrt(2)./(MESH.L.^2);  % actual nodal desnsity
                
                % Display the number of sub-iterations in this 'while' loop
                fprintf(sprintf(' Add/reject node iteration: %d',MESH.add_reject_counter));
                fprintf('\n');
                MESH.add_reject_counter = MESH.add_reject_counter + 1;
            end
            
        else
            %==============================================================
            % ADD/REJECT NODES WHEN DESIRED NODAL DENSITY AND ACTUAL NODAL 
            % DENSITY ARE CLOSE
            % -> effective way to add/reject nodes avoiding oscilations in
            %    the mesh due to variations between added and rejected nodes
            %==============================================================
            % compute the percentage of bars whose misfit with desired length is over 50 %
            pct_bars_whose_misfit_over_50_prev = ...
                (sum(MESH.rel_change_abs>=0.5)/size(MESH.rel_change_abs,1))*100;
            pct_bars_whose_misfit_over_50      = ...
                pct_bars_whose_misfit_over_50_prev - 0.0001;
            MESH.add_reject_counter            = 1; % to initialize
            while pct_bars_whose_misfit_over_50_prev > pct_bars_whose_misfit_over_50
                % save bar_pct_of_misfit_over_50 and MESH from the previous iteration
                pct_bars_whose_misfit_over_50_prev = pct_bars_whose_misfit_over_50;
                MESH_PREV                          = MESH;

                MESH = add_reject_nodes(MESH,GUIDE_MESH,SETTINGS);

                % compute the percentage of bars whose misfit with desired length is over 50 %
                pct_bars_whose_misfit_over_50 = ...
                    (sum(MESH.rel_change_abs>=0.5)/size(MESH.rel_change_abs,1))*100;
                % Display the number of sub-iterations in this 'while' loop
                fprintf(sprintf(' Add/reject node iteration: %d',MESH.add_reject_counter));
                fprintf('\n');
                MESH.add_reject_counter = MESH.add_reject_counter + 1;
            end
            MESH = MESH_PREV;
        end
    else
        %==================================================================
        % ONCE DESIRED NODAL DENSITY IS ACHIEVED, APPLY LOCAL IMPROVEMENTS
        % IN ORDER TO GET HIGHER QUALITY TRIANGLES
        %==================================================================
        % compute the percentage of elements whose q factor is < q_tol
        pct_q_below_q_tol_prev = (sum(MESH.q < SETTINGS.q_tol)/size(MESH.q,1))*100;
        pct_q_below_q_tol      = pct_q_below_q_tol_prev - 0.0001;
        counter                = 0; % to initialize
        n                      = 0; % to initialize
        while pct_q_below_q_tol_prev > pct_q_below_q_tol
            % save pct_q_below_q_tol and MESH from the previous iteration
            pct_q_below_q_tol_prev = pct_q_below_q_tol;
            MESH_PREV           = MESH;
            %==============================================================
            % SMOOTH INTERIOR NODES
            %==============================================================
            MESH = smooth_int_nodes(MESH,GUIDE_MESH,SETTINGS);
            if min(MESH.q) >= SETTINGS.q_tol && mean(MESH.q) >= SETTINGS.mean_q_tol
                MESH_PREV = MESH; break
            end
            
            % compute the percentage of elements whose q factor is < q_tol
            pct_q_below_q_tol = (sum(MESH.q < SETTINGS.q_tol)/size(MESH.q,1))*100;
            % Display the number of sub-iterations in this 'while' loop 
            counter = counter + 1;
            fprintf(repmat('\b',1,n));
            msg     = sprintf('Smoothing iterations: %d',counter);
            fprintf(msg);
            n       = numel(msg);
        end
        MESH = MESH_PREV;
    end
    
    %======================================================================
    % CHECK MESH QUALITY AND DISPLAY INFO
    %======================================================================
    MESH.worst_q = min(MESH.q);
    MESH.mean_q  = mean(MESH.q);
    fprintf(1,'\n Worst q : %7.2f\n', MESH.worst_q);
    fprintf(1,' Mean q  : %7.2f\n', MESH.mean_q);
    
    %======================================================================
    % PLOTS
    %======================================================================
    if SETTINGS.save_figs || SETTINGS.show_figs
        plot_output_data(MESH,SETTINGS)
    end
    
    MESH.iter      = MESH.iter + 1;
    SETTINGS.iplot = SETTINGS.iplot + 1;
end
%==========================================================================
% END OF ITERATION LOOP
%==========================================================================

%==========================================================================
% SAVE DATA
%==========================================================================
if ~isempty(GUIDE_MESH) == 1
    MESH = mesh_info(MESH,GUIDE_MESH);
end
fprintf(1, ' Saving data...');
filename = [SETTINGS.outdir '/MESH'];
save(filename,'MESH');

%==========================================================================
% MAKE MESH COMPATIBLE WITH M2TRI_CYL
%==========================================================================
mesh_format(MESH,GUIDE_MESH,SETTINGS);

%==========================================================================
% DISPLAY ITERATION AND RUNTIME
%==========================================================================
display_progress(MESH.iter,clock0)

fprintf(1, '\n');
fprintf(1, ' CALCULATION FINISHED. Output files in folder:\n "%s"\n',...
    SETTINGS.outdir);
fprintf(1,'========================================================\n');

end % END OF FUNCTION MESH_2D_SPRING