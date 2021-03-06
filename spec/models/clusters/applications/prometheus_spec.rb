require 'rails_helper'

describe Clusters::Applications::Prometheus do
  include_examples 'cluster application core specs', :clusters_applications_prometheus
  include_examples 'cluster application status specs', :cluster_application_prometheus

  describe '.installed' do
    subject { described_class.installed }

    let!(:cluster) { create(:clusters_applications_prometheus, :installed) }

    before do
      create(:clusters_applications_prometheus, :errored)
    end

    it { is_expected.to contain_exactly(cluster) }
  end

  describe '#make_installing!' do
    before do
      application.make_installing!
    end

    context 'application install previously errored with older version' do
      let(:application) { create(:clusters_applications_prometheus, :scheduled, version: '6.7.2') }

      it 'updates the application version' do
        expect(application.reload.version).to eq('6.7.3')
      end
    end
  end

  describe 'transition to installed' do
    let(:project) { create(:project) }
    let(:cluster) { create(:cluster, projects: [project]) }
    let(:prometheus_service) { double('prometheus_service') }

    subject { create(:clusters_applications_prometheus, :installing, cluster: cluster) }

    before do
      allow(project).to receive(:find_or_initialize_service).with('prometheus').and_return prometheus_service
    end

    it 'ensures Prometheus service is activated' do
      expect(prometheus_service).to receive(:update).with(active: true)

      subject.make_installed
    end
  end

  describe '#ready' do
    let(:project) { create(:project) }
    let(:cluster) { create(:cluster, projects: [project]) }

    it 'returns true when installed' do
      application = build(:clusters_applications_prometheus, :installed, cluster: cluster)

      expect(application).to be_ready
    end

    it 'returns false when not_installable' do
      application = build(:clusters_applications_prometheus, :not_installable, cluster: cluster)

      expect(application).not_to be_ready
    end

    it 'returns false when installable' do
      application = build(:clusters_applications_prometheus, :installable, cluster: cluster)

      expect(application).not_to be_ready
    end

    it 'returns false when scheduled' do
      application = build(:clusters_applications_prometheus, :scheduled, cluster: cluster)

      expect(application).not_to be_ready
    end

    it 'returns false when installing' do
      application = build(:clusters_applications_prometheus, :installing, cluster: cluster)

      expect(application).not_to be_ready
    end

    it 'returns false when errored' do
      application = build(:clusters_applications_prometheus, :errored, cluster: cluster)

      expect(application).not_to be_ready
    end
  end

  describe '#prometheus_client' do
    context 'cluster is nil' do
      it 'returns nil' do
        expect(subject.cluster).to be_nil
        expect(subject.prometheus_client).to be_nil
      end
    end

    context "cluster doesn't have kubeclient" do
      let(:cluster) { create(:cluster) }
      subject { create(:clusters_applications_prometheus, cluster: cluster) }

      it 'returns nil' do
        expect(subject.prometheus_client).to be_nil
      end
    end

    context 'cluster has kubeclient' do
      let(:kubernetes_url) { 'http://example.com' }
      let(:k8s_discover_response) do
        {
          resources: [
            {
              name: 'service',
              kind: 'Service'
            }
          ]
        }
      end

      let(:kube_client) { Kubeclient::Client.new(kubernetes_url) }

      let(:cluster) { create(:cluster) }
      subject { create(:clusters_applications_prometheus, cluster: cluster) }

      before do
        allow(kube_client.rest_client).to receive(:get).and_return(k8s_discover_response.to_json)
        allow(subject.cluster).to receive(:kubeclient).and_return(kube_client)
      end

      it 'creates proxy prometheus rest client' do
        expect(subject.prometheus_client).to be_instance_of(RestClient::Resource)
      end

      it 'creates proper url' do
        expect(subject.prometheus_client.url).to eq('http://example.com/api/v1/namespaces/gitlab-managed-apps/service/prometheus-prometheus-server:80/proxy')
      end

      it 'copies options and headers from kube client to proxy client' do
        expect(subject.prometheus_client.options).to eq(kube_client.rest_client.options.merge(headers: kube_client.headers))
      end

      context 'when cluster is not reachable' do
        before do
          allow(kube_client).to receive(:proxy_url).and_raise(Kubeclient::HttpError.new(401, 'Unauthorized', nil))
        end

        it 'returns nil' do
          expect(subject.prometheus_client).to be_nil
        end
      end
    end
  end

  describe '#install_command' do
    let(:kubeclient) { double('kubernetes client') }
    let(:prometheus) { create(:clusters_applications_prometheus) }

    it 'returns an instance of Gitlab::Kubernetes::Helm::InstallCommand' do
      expect(prometheus.install_command).to be_an_instance_of(Gitlab::Kubernetes::Helm::InstallCommand)
    end

    it 'should be initialized with 3 arguments' do
      command = prometheus.install_command

      expect(command.name).to eq('prometheus')
      expect(command.chart).to eq('stable/prometheus')
      expect(command.version).to eq('6.7.3')
      expect(command.values).to eq(prometheus.values)
    end

    context 'application failed to install previously' do
      let(:prometheus) { create(:clusters_applications_prometheus, :errored, version: '2.0.0') }

      it 'should be initialized with the locked version' do
        expect(subject.version).to eq('6.7.3')
      end
    end
  end

  describe '#values' do
    let(:prometheus) { create(:clusters_applications_prometheus) }

    subject { prometheus.values }

    it 'should include prometheus valid values' do
      is_expected.to include('alertmanager')
      is_expected.to include('kubeStateMetrics')
      is_expected.to include('nodeExporter')
      is_expected.to include('pushgateway')
      is_expected.to include('serverFiles')
    end
  end
end
