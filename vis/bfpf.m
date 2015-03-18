function [dipoles, L, moments, weights, state] = bfpf(data,K,vertices,nDipoles,nParticles,Q_location,Q_data,state,flag_all)
% check inputs
nChan = size(data,1);
nTimes = size(data,2);
if ~any(size(vertices)==3)
    error('Vertices must be a 3 x nVert matrix')
elseif size(vertices,2)==3
    vertices = vertices';
end
nVert = size(vertices,2);
if ~exist('Q_location','var') || isempty(Q_location)
    Q_location = 10*eye(3); end
if ~exist('Q_data','var') || isempty(Q_data)
    Q_data = max(abs(data(:)))/3*eye(nChan); end
rng(0);
if exist('state','var') && ~isempty(state)
    flag_state = 1;
else
    flag_state = 0;
end
if ~exist('flag_all','var')
    flag_all = 0;
end
K = double(K); % add check function


if flag_state
    Ktpi = state.Ktpi;
    Kpi_individual = state.Kpi_individual;
    cQ_location = state.cQ_location;
    weights = state.weights;
    L = state.L;
else
    % precalculate pseudo inverse of Lead Field Matrix transposed
    Ktpi = pinv(K');
    Kpi_individual = zeros(size(K'));
    for it = 1:3*nVert
        Kpi_individual(it,:) = pinv(K(:,it)); end
    cQ_location = chol(Q_location);
    state.Ktpi = Ktpi;
    state.Kpi_individual = Kpi_individual;
    state.cQ_location = cQ_location;
    state.nParticles = nParticles;
    % initialize weights
    weights = ones(1,nParticles)/nParticles;
    % initialize dipole locations
    L = randi(nVert,1,nParticles);
end

if flag_all
    for it = 1:nTimes
        nParticles = nVert;
%         weights = ones(1,nParticles)/nParticles;
        % initialize dipole locations
        L = 1:nVert;
        Lold = L;
        moments = zeros(3*nParticles,1);
        for itM = 1:nParticles
            % make linearly constrained minimum variance(LCMV) beamforming filter
%             W0 = Ktpi(:,tri_index(unique(Lold(itM)),nVert))*K(:,tri_index(unique(Lold(itM)),nVert))';
            W0 = eye(nChan);
            % calculate moments vector
            moments(tri_index(itM,nParticles)) = Kpi_individual(tri_index(Lold(itM),nVert),:)*W0'*data(:,it);
        end
        %     moments = sparse([ones(nParticles,1);2*ones(nParticles,1);3*ones(nParticles,1)],repmat(Lold',3,1),moments',3,nVert);
        % update new weights
        y_hat = sum(reshape(bsxfun(@times,moments',K(:,tri_index(Lold,nVert))),[nChan,nParticles,3]),3);
        p_ylx = mvnpdf(bsxfun(@minus,data(:,it),y_hat)',zeros(nChan,1)',Q_data)';
        weights = p_ylx;
    %     weights = weights.*p_ylx;
        % normalize weights
        weights = weights/sum(weights);
    end
end

% iterate
for it = 1:nTimes
    Lold = L;
    % generate random numbers
    w = cQ_location*randn(3,nParticles);
    % displace current locations
    vtemp = vertices(:,Lold) + w;
    % lock new location to existing vertex
    for itPart = 1:nParticles
        [~,L(itPart)] = min(row_pnorm(bsxfun(@minus,vertices,vtemp(:,itPart)),2,'column'));
    end
    moments = zeros(3*nParticles,1);
    for itM = 1:nParticles
        % make linearly constrained minimum variance(LCMV) beamforming filter
%         W0 = Ktpi(:,tri_index(unique(Lold(itM)),nVert))*K(:,tri_index(unique(Lold(itM)),nVert))';
        W0 = eye(nChan);
        % calculate moments vector
        moments(tri_index(itM,nParticles)) = Kpi_individual(tri_index(Lold(itM),nVert),:)*W0'*data(:,it);
    end
%     moments = sparse([ones(nParticles,1);2*ones(nParticles,1);3*ones(nParticles,1)],repmat(Lold',3,1),moments',3,nVert);
    % update new weights
    y_hat = sum(reshape(bsxfun(@times,moments',K(:,tri_index(Lold,nVert))),[nChan,nParticles,3]),3);
    p_ylx = mvnpdf(bsxfun(@minus,data(:,it),y_hat)',zeros(nChan,1)',Q_data)';
    weights = p_ylx;
%     weights = weights.*p_ylx;
    % normalize weights
    weights = weights/sum(weights);
    % resample from L (with replacement) according to importance weights
    L = datasample(L,nParticles,'weights',weights);
end

dipoles = struct('location',[],'moment',[]);
[~,ind] = sort(weights,2,'ascend');
for it = 1:nDipoles
    dipoles(it).location = vertices(:,L(ind(it)));
    dipoles(it).moment = moments(tri_index(ind(it),nParticles));
end

state.weights = weights;
state.L = L;


function index = tri_index(index,nVert)
if iscolumn(index)
    index = index'; end
index = [index,index+nVert,index+2*nVert];