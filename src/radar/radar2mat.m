function [ data, x1, x2, x3, fields ] = radar2mat( radar, varargin )
%RADAR2MAT Convert an aligned radar volume to 3d-matrix
%
% [ data, x1, x2, x3 ] = radar2mat( radar, varargin )
%
% Example:
%    [ data, x1, x2, x3 ] = radar2mat( radar, 'fields', {'dz', 'vr'}, 'r_max', 150000 )
%
% Inputs:
%   radar        radar struct (required)
%   fields       cell array of fields to return (default: {'dz', 'vr'})
%   r_max        max radius for polar or cartesian data in meters (default: 150000m = 150km)
%
% Named inputs
%   coords       'polar' | 'cartesian' (default: 'polar')
%   r_min        min radius for polar data in meters (default: 2125)
%   r_res        range resolution (default: 250m)
%   az_res       azimuth resolution (default: 0.5)
%   dim          pixel dimension for Cartesian data (default: 500)
%   sweeps       the sweep indices to select (default: all available elevations)
%   elevs        if set, select sweeps by elevation angle instead of
%                number, using nearest-neighbor interpolation to match to
%                the desired elevations
%   output_format  cell | struct
%   ydirection   'xy' | 'ij'. This specifies whether the y coordinates
%                of pixels are decreasing ('ij') or increasing ('xy')
%                along the first dimension of the array. The default
%                is 'xy', which makes the output compatible with
%                griddedInterpolant.
%   interp_method: Interpolation method for use within radarInterpolant.
%                Default is 'nearest'.
%   max_interp_dist: Tolerance in degrees for matching requested elevation
%                angles (defualt: 1.0)
%
% Outputs:
%   data         struct or cell array of 3D data matrices of size m x n x p
%   x1           vector of coordinates for first dimension (m x 1)
%   x2           vector of coordinates for second dimension (n x 1)
%   x3           vector of coordinates for third dimension (p x 1)
%
% For polar coordinates the dimension order is range, az, elev
%
% For Cartesian data, the dimension order is y, x, z, with the y dimension
% stored in "gridded data" format as opposed to "image format". That is,
% the first row has the smallest y coordinate. This makes it compatible
% with griddedInterpolant but an extra step is required to view it as an
% image in the correct orientation. For plotting within MATLAB, use "axis
% xy" to set the axes to the correct orientation. For saving as an image,
% either set 'ydirection' to 'ij', or use the flip function to flip the
% first dimension order yourself.
%
% See also MAT2MAT, GRIDDEDINTERPOLANT, FLIP, AXIS

FLAG_START = 131067;

DEFAULT_FIELDS = {'all'};
DEFAULT_COORDS = 'polar';
DEFAULT_R_MIN  = 2125;
DEFAULT_R_MAX  = 150000;
DEFAULT_R_RES  = 250;
DEFAULT_AZ_RES = 0.5;
DEFAULT_DIM    = 500;
DEFAULT_SWEEPS = [];
DEFAULT_ELEVS  = [];
DEFAULT_INTERP_METHOD = 'nearest';
DEFAULT_OUTPUT_FORMAT = 'struct';
DEFAULT_YDIRECTION = 'xy';
DEFAULT_MAX_INTERP_DIST = 1.0; % maximum interpolation distance for elevation angles

p = inputParser;

addRequired(p, 'radar',    @isstruct);

addParameter(p, 'fields',  DEFAULT_FIELDS, @(x) iscell(x) || ischar(x));
addParameter(p,  'r_max',   DEFAULT_R_MAX, @(x) isscalar(x) && x >= 0 );
addParameter(p, 'coords',  DEFAULT_COORDS, @(x) any(validatestring(x,{'polar','cartesian'})));
addParameter(p,  'r_min',   DEFAULT_R_MIN, @(x) isscalar(x) && x >= 0);
addParameter(p,  'r_res',   DEFAULT_R_RES, @(x) isscalar(x) && x > 0);
addParameter(p, 'az_res',  DEFAULT_AZ_RES, @(x) isscalar(x) && x > 0);
addParameter(p,    'dim',     DEFAULT_DIM, @(x) isscalar(x) && x > 0);
addParameter(p, 'sweeps',  DEFAULT_SWEEPS, @(x) validateattributes(x,{'numeric'},{'nonempty','positive','integer'}));
addParameter(p,  'elevs',   DEFAULT_ELEVS, @(x) validateattributes(x,{'numeric'},{'nonempty','positive'}));
addParameter(p,  'interp_method',   DEFAULT_INTERP_METHOD, @(x) ischar(x));
addParameter(p,  'output_format',   DEFAULT_OUTPUT_FORMAT, @(x) any(validatestring(x,{'struct','cell'})));
addParameter(p,  'max_interp_dist', DEFAULT_MAX_INTERP_DIST, @(x) isscalar(x) && x >= 0);
addParameter(p,  'use_ground_range',   true, @islogical);
addParameter(p, 'ydirection',  DEFAULT_YDIRECTION, @(x) any(validatestring(x,{'ij','xy'})));

parse(p, radar, varargin{:});

params = p.Results;

% Get list of requested fields
get_available_fields = strcmp(params.fields, 'all');
if get_available_fields
    fields = {'dz', 'vr', 'sw', 'dr', 'ph', 'rh'};
else
    fields = params.fields;
end

% Restrict to those that are present in scan
is_present = cellfun(@(f) isfield(radar, f) && ~isempty(radar.(f)), fields);
fields  = fields(is_present);

% Warn if requested fields are missing
if ~all(is_present) && ~get_available_fields
    warning('Some requested fields are missing. Check output fields');
end

% Prepare the output cell array
n_fields = numel(fields);
data = cell(n_fields, 1);


% Preprocess each product to preserve one sweep per elevation angle
for f = 1:n_fields
    radar.(fields{f}).sweeps = unique_elev_sweeps(radar, fields{f});
end

% Get list of requested elevation angles. Use params.elevs if set,
% otherwise select from the elevation angles of the first requested field.
if ~isempty(params.elevs)
    requested_elevs = params.elevs;
else
    % all available elevations
    requested_elevs = [radar.(fields{1}).sweeps.elev];
    
    % subselect if particular sweep indices are requested
    if ~isempty(params.sweeps)
        requested_elevs = requested_elevs(params.sweeps);
    end
end

% Select sweeps for each field that are as close as possible to desired
% elevation
sweeps = cell(n_fields, 1);
available_elevs = cell(n_fields, 1);
for f = 1:n_fields
    
    available_elevs{f} = [radar.(fields{f}).sweeps.elev];
    
    if length(available_elevs{f}) == 1
        if length(requested_elevs) == 1
            sweeps{f} = 1;
        else
            error('Only one sweep available: cannot interpolate');
        end
    else
        % For each requested elevation, find index of nearest available elevation
        inds = 1:length(available_elevs{f});
        sweeps{f} = interp1(available_elevs{f}, inds, requested_elevs, 'nearest', 'extrap');
        if any(isnan(sweeps{f}))
            warning('Unable to match requested sweeps, removing unmatched sweeps.')
            sweeps{f} = sweeps{f}(~isnan(sweeps{f}));
        end
    end
    
    % Check if any selected sweeps exceed the maximum interpolation distance
    interp_dist = abs(available_elevs{f}(sweeps{f})) - requested_elevs;
    is_bad = interp_dist > params.max_interp_dist;
    if any(is_bad)
        error('Failed to match elevations %s. Available elevs are %s, max_dist is %.2f.', ...
            mat2str(requested_elevs(is_bad)), ...
            mat2str(available_elevs{f}), ...
            params.max_interp_dist);
    end
end

% Set output elevations using dz if available, else first field
f = find(strcmp('dz', fields));
if isempty(f)
    f = 0;
end
output_elevs = available_elevs{f}(sweeps{f});

n_sweeps = numel(requested_elevs);

% Construct R and PHI, the range and azimuth coordinates of the query
% points. These are the same for each product and each sweep

switch params.coords
    
    case 'polar'
        
        % Query points
        r   = params.r_min  : params.r_res  : params.r_max;
        phi = params.az_res : params.az_res : 360;
        [PHI, R] = meshgrid(phi, r);
        
        % Coordinates of three dimensions in output array
        x1 = r;
        x2 = phi;
        x3 = output_elevs;
        
    case 'cartesian'
        
        % Query points
        x = linspace (-params.r_max, params.r_max, params.dim);
        switch params.ydirection
            case 'xy'
                y = x;
            case 'ij'
                y = -x;
        end
        [X, Y] = meshgrid(x, y);
        [PHI, R] = cart2pol(X, Y);
        PHI = pol2cmp(PHI);  % convert from radians to compass heading
        
        % Coordinates of three dimensions in output array
        x1 = y;
        x2 = x;
        x3 = output_elevs;
        
    otherwise
        error('Bad coordinate system')
end


% Number of rows and columns in output
[m, n] = size(PHI);

% Now populate the data arrays
for f = 1:n_fields
    data{f} = nan(m, n, n_sweeps);
    for i = 1:n_sweeps
        
        % Extract data
        sweep_num = sweeps{f}(i);
        sweep = radar.(fields{f}).sweeps(sweep_num);
        [az, range] = get_az_range(sweep);
        vals = sweep.data;
        
        % Convert from slant range to ground range
        if params.use_ground_range
            range = slant2ground(range, sweep.elev);
        end
        
        % Set special non-numeric values to nan
        vals(vals >= FLAG_START) = nan;
        
        % Create the interpolant
        F = radarInterpolant(vals, az, range, params.interp_method);
        
        % Interpolate onto query points and populate slice of output array
        data{f}(:,:,i) = F(R, PHI);
    end
end

switch params.output_format
    case 'cell'
        % do nothing
    case 'struct'
        data = cell2struct(data(:), fields(:), 1);
    otherwise
        error('Bad output format')
end

end
